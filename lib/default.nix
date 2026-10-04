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
    recursiveUpdate
    types
    unique
    ;

  inherit (builtins)
    attrNames
    functionArgs
    head
    isFunction
    isString
    listToAttrs
    mapAttrs
    match
    tryEval
    ;

  leaves = node: if node == null then [ ] else srctree.lib.alg.leaves node;

  leafContents = node: map (n: n.content) (leaves node);

  children = node: if node == null then [ ] else node.children or [ ];

  mapChildren = f: node: listToAttrs (map (c: nameValuePair c.name (f c)) (children node));

  childContents = mapChildren (n: n.content);

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
      hm = home-manager.nixosModules.home-manager;
      osMods = mods: mods.nixos;

      osDefaults =
        { config, ... }:
        {
          system.stateVersion = mkDefault config.system.nixos.release;
        };
    };

    darwin = {
      build = nix-darwin.lib.darwinSystem;
      hm = home-manager.darwinModules.home-manager;
      osMods = mods: mods.darwin;

      osDefaults =
        { config, ... }:
        {
          system.stateVersion = mkDefault config.system.maxStateVersion;
        };
    };
  };

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
        name = node.name;
        inherit modules os;
        inherit (host) platform users;
      }
    else
      null;

  rawTree = srctree.lib.load root;
  rootTree = if rawTree == null then { } else srctree.lib.toAttrs rawTree;

  # `{ inputs, ... }: final: prev: { }` overlays get their arguments applied here:
  # nixpkgs calls with `final prev`, and the pattern match would force `final` too early.
  applyOverlayArgs =
    def: if isFunction def && (functionArgs def) != { } then def { inputs = userInputs; } else def;

  packageDefs = childContents (rootTree.packages or null);
  overlays = mapAttrs (_: applyOverlayArgs) (childContents (rootTree.overlays or null));

  hosts = filterAttrs (_: h: h != null && !(h.os == "darwin" && nix-darwin == null)) (
    mapChildren discoverHost (rootTree.hosts or null)
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

  loadMetaModules =
    pkgs:
    let
      raw = metatree.lib.load pkgs (root + "/modules");
    in
    if raw == null then { } else metatree.lib.toAttrs raw;

  metaModuleSets = genAttrs hostPlatforms (system: loadMetaModules nixpkgs.legacyPackages.${system});

  mkMetaModules = pkgs: metaModuleSets.${pkgs.system} or (loadMetaModules pkgs);

  loadModules =
    system:
    let
      attrs = metaModuleSets.${system};
      home = attrs.home or { };
    in
    {
      shared = leafContents (attrs.shared or null);
      nixos = leafContents (attrs.nixos or null);
      darwin = leafContents (attrs.darwin or null);
      homeShared = leafContents (home.shared or null);
      homeUsers = mapChildren leafContents (home.users or null);
    };

  moduleSets = genAttrs hostPlatforms loadModules;

  mkHost =
    name: host:
    let
      b = builders.${host.os} or (throw "unsupported host platform: ${host.platform}");

      mods = moduleSets.${host.platform};

      hostInputs = recursiveUpdate userInputs {
        self.lib.metaModules = metaModuleSets.${host.platform};
      };

      osDefaults = {
        networking.hostName = mkDefault name;
      };

      hmModules = optionals (home-manager != null) [
        b.hm
        {
          home-manager = {
            extraSpecialArgs.inputs = hostInputs;
            sharedModules = mods.homeShared;
            useGlobalPkgs = true;
            useUserPackages = true;

            users = genAttrs host.users (
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
      modules =
        host.modules
        ++ [
          osDefaults
          b.osDefaults
        ]
        ++ mods.shared
        ++ (b.osMods mods)
        ++ hmModules;

      specialArgs.inputs = hostInputs;
      system = host.platform;
    };

in
flake-parts.lib.mkFlake { inputs = userInputs; } {
  systems = moduleSystems;

  imports = leafContents (rootTree.flake or null);

  flake = {
    nixosConfigurations = mapAttrs mkHost (hostsFor "linux");
    darwinConfigurations = mapAttrs mkHost (hostsFor "darwin");

    lib = {
      inherit rootTree;
      metaModulesFor = mkMetaModules;
    };

    inherit overlays;
  };

  perSystem = { pkgs, ... }: {
    packages = mapAttrs (_: def: if isFunction def then pkgs.callPackage def { } else def) packageDefs;
  };
}
