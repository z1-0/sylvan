{
  inputs,
  userInputs,
  root,
}:

let
  nixpkgs = userInputs.nixpkgs;

  nix-darwin = userInputs.nix-darwin or null;
  home-manager = userInputs.home-manager or null;

  inherit (inputs) flake-parts metatree srctree;

  nixpkgsLib = flake-parts.inputs.nixpkgs-lib.lib;

  inherit (nixpkgsLib)
    attrValues
    evalModules
    filterAttrs
    genAttrs
    mkDefault
    mkForce
    mkOption
    nameValuePair
    optionals
    types
    unique
    ;

  inherit (builtins)
    attrNames
    filter
    hasAttr
    head
    isFunction
    isString
    listToAttrs
    mapAttrs
    match
    tryEval
    ;

  # Tree helpers

  leaves = node: if node == null then [ ] else srctree.lib.alg.leaves node;

  leafContents = node: map (n: n.content) (leaves node);

  children = node: if node == null then [ ] else node.children or [ ];

  mapChildren = f: node: listToAttrs (map (c: nameValuePair c.name (f c)) (children node));

  childContents = mapChildren (n: n.content);

  # Platform helpers

  osOf =
    system:
    if isString system then
      let
        m = match ".*-(linux|darwin)" system;
      in
      if m == null then null else head m
    else
      null;

  builders = {
    linux = {
      build = nixpkgs.lib.nixosSystem;
      osMods = mods: mods.nixos;
      hm = home-manager.nixosModules.home-manager;
    };

    darwin = {
      build = nix-darwin.lib.darwinSystem;
      osMods = mods: mods.darwin;
      hm = home-manager.darwinModules.home-manager;
    };
  };

  # Safe evaluation

  try =
    v:
    let
      r = tryEval v;
    in
    if r.success then r.value else null;

  probeModule = {
    options = {
      nixpkgs.hostPlatform = mkOption {
        type = types.unspecified;
        default = null;
      };

      nixpkgs.system = mkOption {
        type = types.unspecified;
        default = null;
      };

      users.users = mkOption {
        type = types.unspecified;
        default = { };
      };
    };

    config._module.check = mkForce false;
  };

  probeHost =
    modules:
    let
      cfg =
        (evalModules {
          modules = modules ++ [ probeModule ];

          specialArgs.inputs = userInputs;
        }).config;

      platform =
        if cfg.nixpkgs.hostPlatform != null then cfg.nixpkgs.hostPlatform else cfg.nixpkgs.system;
    in
    {
      inherit platform;
      users = attrNames cfg.users.users;
    };

  discoverHost =
    node:
    let
      modules = leafContents node;
      host = try (probeHost modules);
      os = osOf host.platform;
    in
    if host != null && os != null then
      {
        inherit modules os;
        inherit (host) platform users;
      }
    else
      null;

  # Source tree

  rawTree = srctree.lib.load root;
  tree = if rawTree == null then { } else srctree.lib.toAttrs rawTree;

  packageDefs = childContents (tree.packages or null);
  overlays = childContents (tree.overlays or null);

  hosts = filterAttrs (_: h: h != null && !(h.os == "darwin" && nix-darwin == null)) (
    mapChildren discoverHost (tree.hosts or null)
  );

  hostsFor = os: filterAttrs (_: h: h.os == os) hosts;

  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  hostPlatforms = unique (map (h: h.platform) (attrValues hosts));
  moduleSystems = unique (defaultSystems ++ hostPlatforms);

  # Shared modules

  loadModules =
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      raw = metatree.lib.load pkgs (root + "/modules");
      attrs = if raw == null then { } else metatree.lib.toAttrs raw;
      home = attrs.home or { };
    in
    {
      shared = leafContents (attrs.shared or null);
      nixos = leafContents (attrs.nixos or null);
      darwin = leafContents (attrs.darwin or null);
      homeShared = leafContents (home.shared or null);
      homeUsers = mapChildren leafContents (home.users or null);
    };

  moduleSets = genAttrs moduleSystems loadModules;

  # Host builder

  mkHost =
    name: host:
    let
      b = builders.${host.os} or (throw "unsupported host platform: ${host.platform}");

      mods = moduleSets.${host.platform};

      validUsers = filter (u: hasAttr u mods.homeUsers) host.users;

      hmModules = optionals (validUsers != [ ] && home-manager != null) [
        b.hm
        {
          home-manager = {
            extraSpecialArgs.inputs = userInputs;
            sharedModules = mods.homeShared;
            useGlobalPkgs = true;
            useUserPackages = true;

            users = genAttrs validUsers (
              u: { osConfig, ... }: {
                home.stateVersion = mkDefault osConfig.system.stateVersion;
                imports = mods.homeUsers.${u} or [ ];
              }
            );
          };
        }
      ];
    in
    b.build {
      modules = host.modules ++ mods.shared ++ (b.osMods mods) ++ hmModules;

      specialArgs.inputs = userInputs;
      system = host.platform;
    };

in
flake-parts.lib.mkFlake { inputs = userInputs; } {
  systems = moduleSystems;

  imports = leafContents (tree.flake or null);

  flake = {
    nixosConfigurations = mapAttrs mkHost (hostsFor "linux");
    darwinConfigurations = mapAttrs mkHost (hostsFor "darwin");
    inherit overlays;
  };

  perSystem = { pkgs, ... }: {
    packages = mapAttrs (_: def: if isFunction def then pkgs.callPackage def { } else def) packageDefs;
  };
}
