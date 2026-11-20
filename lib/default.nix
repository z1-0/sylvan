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
    warn
    ;

  inherit (builtins)
    attrNames
    deepSeq
    functionArgs
    isAttrs
    isFunction
    isString
    listToAttrs
    mapAttrs
    tryEval
    typeOf
    ;

  leaves = node: if node == null then [ ] else srctree.lib.alg.leaves node;

  leafContents = node: map (n: n.content) (leaves node);

  children = node: if node == null then [ ] else node.children or [ ];

  mapChildren = f: node: listToAttrs (map (c: nameValuePair c.name (f c)) (children node));

  childContents = mapChildren (n: n.content);

  describePlatform =
    platform:
    if isString platform then
      platform
    else if isAttrs platform then
      let
        inner = platform.config or platform.system or null;
      in
      if isString inner then
        inner
      else if inner == null then
        "an attribute set without a string `config' or `system'"
      else
        "an attribute set whose `config' / `system' is of type ${typeOf inner}"
    else
      "a value of type ${typeOf platform}";

  resolvePlatform =
    platform:
    if
      !(isString platform || (isAttrs platform && isString (platform.config or platform.system or null)))
    then
      { status = "invalid"; }
    else
      let
        elaborated = tryDeep (
          let
            e = nixpkgsLib.systems.elaborate platform;
          in
          {
            inherit (e) system;
            kernel = e.parsed.kernel.name;
          }
        );
      in
      if !elaborated.success then
        { status = "unsupported"; }
      else if elaborated.value.kernel == "linux" || elaborated.value.kernel == "darwin" then
        {
          status = "supported";
          inherit (elaborated.value) kernel system;
        }
      else
        { status = "unsupported"; };

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

  tryDeep = v: tryEval (deepSeq v v);

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
      probe = probeHost modules;
      platform = tryDeep probe.platform;
    in
    if !platform.success then
      warn "sylvan skipped host `${node.name}' because evaluating `nixpkgs.hostPlatform' / `nixpkgs.system' failed." null
    else if platform.value == null then
      warn "sylvan skipped host `${node.name}' because neither `nixpkgs.hostPlatform' nor `nixpkgs.system' is set." null
    else
      let
        raw = platform.value;
        resolved = resolvePlatform raw;
      in
      if resolved.status == "invalid" then
        warn "sylvan skipped host `${node.name}' because `nixpkgs.hostPlatform' / `nixpkgs.system' is ${describePlatform raw}." null
      else if resolved.status == "unsupported" then
        warn "sylvan skipped host `${node.name}' because it targets `${describePlatform raw}', but only NixOS and nix-darwin hosts are supported." null
      else
        {
          inherit modules;
          inherit (node) name;
          inherit (probe) users;
          inherit (resolved) kernel system;
        };

  rawTree = srctree.lib.load root;
  rootTree = if rawTree == null then { } else srctree.lib.toAttrs rawTree;

  # `{ inputs }: final: prev: { }` overlays get the flake inputs; plain overlays pass through.
  applyOverlayArgs =
    def: if isFunction def && (functionArgs def) ? inputs then def { inputs = userInputs; } else def;

  packageDefs = childContents (rootTree.packages or null);
  overlays = mapAttrs (_: applyOverlayArgs) (childContents (rootTree.overlays or null));

  hosts = filterAttrs (_: h: h != null && !(h.kernel == "darwin" && nix-darwin == null)) (
    mapChildren discoverHost (rootTree.hosts or null)
  );

  hostsFor = kernel: filterAttrs (_: h: h.kernel == kernel) hosts;

  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  hostPlatforms = unique (map (h: h.system) (attrValues hosts));
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
      b = builders.${host.kernel};

      mods = moduleSets.${host.system};

      hostInputs = recursiveUpdate userInputs {
        self.lib.metaModules = metaModuleSets.${host.system};
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
              u: { config, ... }: {
                home.stateVersion = mkDefault config.home.version.release;
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
