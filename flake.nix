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
          settingsApiKeys =
            if builtins.hasAttr "api-keys" cfg.settings then cfg.settings."api-keys" else [ ];
          hasConfiguredApiKeys = builtins.isList settingsApiKeys && settingsApiKeys != [ ];
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

            stateDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/auth2api";
              description = ''
                Writable directory used for OAuth token storage, generated stats,
                and as the service working directory.
              '';
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 8317;
              description = ''
                TCP port auth2api listens on. This is used for the generated
                configuration and for openFirewall. When configFile is set, keep
                this value in sync with the port in that external YAML file if
                openFirewall is enabled.
              '';
            };

            configFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "/run/secrets/auth2api.yaml";
              description = ''
                Path to an existing auth2api YAML configuration file. When unset,
                services.auth2api.settings is rendered to a Nix store YAML file.
                Use an absolute runtime path such as /run/secrets/auth2api.yaml
                for secret-bearing configuration that must not be copied into
                the Nix store.
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
                Secret values such as api-keys will be copied into the Nix store;
                use configFile for deployments that need to keep secrets out of
                the store.
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
                assertion = cfg.configFile != null || hasConfiguredApiKeys;
                message = ''
                  services.auth2api requires either services.auth2api.configFile
                  or a non-empty services.auth2api.settings."api-keys" list.
                  Without one, auth2api attempts to auto-generate an API key and
                  write it back to the generated Nix store config file, which is
                  read-only under NixOS.
                '';
              }
            ];

            services.auth2api.settings = lib.mkDefault {
              host = "127.0.0.1";
              port = cfg.port;
              "auth-dir" = toString cfg.stateDir;
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
                StateDirectory = lib.mkIf (cfg.stateDir == "/var/lib/auth2api") "auth2api";
                WorkingDirectory = cfg.stateDir;
                ExecStart = "${lib.getExe cfg.package} --config=${configFile}";
                Restart = "on-failure";
                RestartSec = 5;
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [ cfg.stateDir ];
              };
            };

            systemd.tmpfiles.rules = [
              "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
            ];

            networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
          };
        };

      darwinModule =
        { config, lib, pkgs, ... }:
        let
          cfg = config.services.auth2api;
          yamlFormat = pkgs.formats.yaml { };
          settingsApiKeys =
            if builtins.hasAttr "api-keys" cfg.settings then cfg.settings."api-keys" else [ ];
          hasConfiguredApiKeys = builtins.isList settingsApiKeys && settingsApiKeys != [ ];
          generatedConfig = yamlFormat.generate "auth2api.yaml" cfg.settings;
          configFile = if cfg.configFile != null then cfg.configFile else generatedConfig;
          hasUser = cfg.user != null;
          hasGroup = cfg.group != null;
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
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "_auth2api";
              description = ''
                Optional user account under which the auth2api launchd daemon
                runs. When null, launchd runs the daemon as root. Set this to an
                existing macOS user for a less-privileged system-wide service.
              '';
            };

            group = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "_auth2api";
              description = ''
                Optional group account under which the auth2api launchd daemon
                runs. When null, launchd uses the default group for the selected
                user, or root's default group when services.auth2api.user is null.
              '';
            };

            stateDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/db/auth2api";
              description = ''
                Writable directory used for OAuth token storage, generated stats,
                and as the launchd daemon working directory on macOS.
              '';
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 8317;
              description = ''
                TCP port auth2api listens on. This is used for the generated
                configuration. When configFile is set, keep this value in sync
                with the port in that external YAML file.
              '';
            };

            configFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "/run/secrets/auth2api.yaml";
              description = ''
                Path to an existing auth2api YAML configuration file. When unset,
                services.auth2api.settings is rendered to a Nix store YAML file.
                Use an absolute runtime path outside the Nix store for
                secret-bearing configuration that must remain writable or must
                not be copied into the store.
              '';
            };

            settings = lib.mkOption {
              type = yamlFormat.type;
              default = { };
              example = {
                host = "127.0.0.1";
                port = 8317;
                "auth-dir" = "/var/db/auth2api";
                "api-keys" = [ "sk-change-me" ];
                debug = "errors";
              };
              description = ''
                auth2api configuration rendered as YAML when configFile is unset.
                Secret values such as api-keys will be copied into the Nix store;
                use configFile for deployments that need to keep secrets out of
                the store. As with the NixOS module, auth2api needs either an
                external configFile or an explicit non-empty api-keys list because
                it cannot write generated keys back to a read-only Nix store file.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            assertions = [
              {
                assertion = cfg.configFile != null || hasConfiguredApiKeys;
                message = ''
                  services.auth2api requires either services.auth2api.configFile
                  or a non-empty services.auth2api.settings."api-keys" list.
                  Without one, auth2api attempts to auto-generate an API key and
                  write it back to the generated Nix store config file, which is
                  read-only when rendered by the Nix module.
                '';
              }
              {
                assertion = builtins.substring 0 1 cfg.stateDir == "/";
                message = "services.auth2api.stateDir must be an absolute path for launchd.";
              }
              {
                assertion = cfg.configFile == null || builtins.substring 0 1 cfg.configFile == "/";
                message = "services.auth2api.configFile must be null or an absolute path for launchd.";
              }
            ];

            services.auth2api.settings = lib.mkDefault {
              host = "127.0.0.1";
              port = cfg.port;
              "auth-dir" = toString cfg.stateDir;
            };

            system.activationScripts.auth2api.text = ''
              mkdir -p '${cfg.stateDir}' /var/log/auth2api
              chmod 0750 '${cfg.stateDir}'
              chmod 0755 /var/log/auth2api
            '' + lib.optionalString (hasUser || hasGroup) ''
              chown ${lib.optionalString hasUser cfg.user}${lib.optionalString hasGroup ":${cfg.group}"} '${cfg.stateDir}' /var/log/auth2api
            '';

            launchd.daemons.auth2api = {
              serviceConfig = {
                Label = "org.nixos.auth2api";
                ProgramArguments = [
                  (lib.getExe cfg.package)
                  "--config=${configFile}"
                ];
                WorkingDirectory = cfg.stateDir;
                StandardOutPath = "/var/log/auth2api/auth2api.log";
                StandardErrorPath = "/var/log/auth2api/auth2api.err.log";
                RunAtLoad = true;
                KeepAlive = true;
              } // lib.optionalAttrs hasUser {
                UserName = cfg.user;
              } // lib.optionalAttrs hasGroup {
                GroupName = cfg.group;
              };
            };
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
      darwinModules.default = darwinModule;
      darwinModules.auth2api = darwinModule;
    };
}
