{
  description = "auth2api OAuth-to-API proxy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    let
      nixosModule =
        { config, lib, pkgs, ... }:
        let
          cfg = config.services.auth2api;
          yamlFormat = pkgs.formats.yaml { };
          generatedConfig = yamlFormat.generate "auth2api.yaml" cfg.settings;
          configFile = if cfg.configFile != null then cfg.configFile else generatedConfig;
        in
        {
          options.services.auth2api = {
            enable = lib.mkEnableOption "auth2api OAuth-to-API proxy";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.default";
              description = "auth2api package to run.";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "auth2api";
              description = "User account under which auth2api runs.";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "auth2api";
              description = "Group account under which auth2api runs.";
            };

            configFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to an existing auth2api YAML configuration file. Use this
                for writable or secret-backed configs, such as a file in /run or
                /var/lib/auth2api. When unset, services.auth2api.settings is
                rendered to a read-only Nix store YAML file and must include at
                least one api-key because auth2api writes generated keys back to
                the config file when none are configured.
              '';
            };

            settings = lib.mkOption {
              type = yamlFormat.type;
              default = { };
              example = {
                host = "0.0.0.0";
                port = 8317;
                "auth-dir" = "/var/lib/auth2api";
                "api-keys" = [ "sk-change-me" ];
                debug = "errors";
              };
              description = ''
                auth2api configuration rendered as YAML when configFile is unset.
                When using the generated store config, api-keys must contain at
                least one key so auth2api does not try to generate and write one
                back to the read-only Nix store at startup. Secret values such as
                api-keys will be copied into the Nix store; use configFile for
                deployments that need to keep secrets out of the store.
              '';
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Open the configured TCP port in the firewall.";
            };
          };

          config = lib.mkIf cfg.enable {
            assertions = [
              {
                assertion =
                  cfg.configFile != null
                  || (cfg.settings ? "api-keys" && cfg.settings."api-keys" != [ ]);
                message = ''
                  services.auth2api requires either services.auth2api.configFile
                  or at least one services.auth2api.settings.api-keys entry.
                  auth2api auto-generates and writes an API key when none are
                  configured, which cannot work with the read-only Nix store
                  config generated from services.auth2api.settings.
                '';
              }
            ];

            services.auth2api.settings = lib.mkDefault {
              host = "127.0.0.1";
              port = 8317;
              "auth-dir" = "/var/lib/auth2api";
            };

            users.users = lib.mkIf (cfg.user == "auth2api") {
              auth2api = {
                isSystemUser = true;
                inherit (cfg) group;
                home = "/var/lib/auth2api";
              };
            };
            users.groups = lib.mkIf (cfg.group == "auth2api") { auth2api = { }; };

            systemd.services.auth2api = {
              description = "auth2api OAuth-to-API proxy";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                Group = cfg.group;
                StateDirectory = "auth2api";
                WorkingDirectory = "/var/lib/auth2api";
                ExecStart = "${lib.getExe cfg.package} --config=${configFile}";
                Restart = "on-failure";
                RestartSec = 5;
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [ "/var/lib/auth2api" ];
              };
            };

            networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.settings.port ];
          };
        };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.buildNpmPackage {
          pname = "auth2api";
          version = "1.0.0";
          src = ./.;

          npmDeps = pkgs.importNpmLock { npmRoot = ./.; };
          nativeBuildInputs = [
            pkgs.importNpmLock.npmConfigHook
            pkgs.makeWrapper
          ];

          npmBuildScript = "build";

          installPhase = ''
            runHook preInstall

            mkdir -p $out/lib/auth2api $out/bin
            cp -r dist node_modules package.json $out/lib/auth2api/

            makeWrapper ${pkgs.nodejs_20}/bin/node $out/bin/auth2api \
              --add-flags $out/lib/auth2api/dist/index.js

            runHook postInstall
          '';

          meta = {
            description = "Lightweight OAuth-to-API proxy for Claude, ChatGPT Codex, and Cursor";
            homepage = "https://github.com/AmazingAng/auth2api";
            license = pkgs.lib.licenses.mit;
            mainProgram = "auth2api";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs_20
            nodePackages.npm
          ];
        };
      }
    )
    // {
      nixosModules.default = nixosModule;
      nixosModules.auth2api = nixosModule;
    };
}
