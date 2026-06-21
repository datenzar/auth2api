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
          authDir = cfg.authDir;
          launchScript = pkgs.writeShellScript "auth2api-launchd" ''
            set -eu

            while ! compgen -G ${lib.escapeShellArg "${authDir}/claude-*.json"} > /dev/null \
              && ! compgen -G ${lib.escapeShellArg "${authDir}/codex-*.json"} > /dev/null \
              && ! compgen -G ${lib.escapeShellArg "${authDir}/cursor-*.json"} > /dev/null; do
              echo "auth2api is waiting for an OAuth token in ${authDir}. Run auth2api login, or copy an existing claude-*.json, codex-*.json, or cursor-*.json token file into that directory." >&2
              sleep 30
            done

            exec ${lib.escapeShellArg (lib.getExe cfg.package)} --config=${lib.escapeShellArg configFile}
          '';
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
              default = "_auth2api";
              description = ''
                User account under which the auth2api launchd daemon runs. The
                default _auth2api account is provisioned by the activation script.
                Set to null only if you explicitly want launchd to run as root.
              '';
            };

            group = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "_auth2api";
              description = ''
                Group account under which the auth2api launchd daemon runs. The
                default _auth2api group is provisioned by the activation script.
                Set to null to use the selected user's default group.
              '';
            };

            uid = lib.mkOption {
              type = lib.types.int;
              default = 350;
              description = ''
                macOS UniqueID used when provisioning the default _auth2api user.
                Change this if the UID is already allocated on your system.
              '';
            };

            gid = lib.mkOption {
              type = lib.types.int;
              default = 350;
              description = ''
                macOS PrimaryGroupID used when provisioning the default _auth2api
                group. Change this if the GID is already allocated on your system.
              '';
            };

            stateDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/db/auth2api";
              description = ''
                Writable directory used for generated stats and as the launchd
                daemon working directory on macOS.
              '';
            };

            authDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/db/auth2api";
              description = ''
                Writable directory used for OAuth token storage and for the
                launchd startup token-file guard. When configFile points at an
                external YAML file, keep this value in sync with that file's
                auth-dir so launchd waits in the same directory auth2api reads.
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
                debug = "errors";
              };
              description = ''
                auth2api configuration rendered as YAML when configFile is unset.
                Secret values such as api-keys will be copied into the Nix store;
                use configFile for deployments that need to keep secrets out of
                the store. Generated store-backed api-keys are rejected unless
                allowStoreApiKeys is explicitly enabled.
              '';
            };

            allowStoreApiKeys = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Explicitly allow services.auth2api.settings."api-keys" to be
                rendered into a Nix store YAML file when configFile is unset.
                Prefer configFile for secret-bearing deployments.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            assertions = [
              {
                assertion = cfg.configFile != null || (hasConfiguredApiKeys && cfg.allowStoreApiKeys);
                message = ''
                  services.auth2api requires services.auth2api.configFile for
                  secret-bearing runtime configuration. To render
                  services.auth2api.settings."api-keys" into the Nix store
                  anyway, set services.auth2api.allowStoreApiKeys = true.
                '';
              }
              {
                assertion = builtins.substring 0 1 cfg.stateDir == "/";
                message = "services.auth2api.stateDir must be an absolute path for launchd.";
              }
              {
                assertion = builtins.substring 0 1 cfg.authDir == "/";
                message = "services.auth2api.authDir must be an absolute path for launchd.";
              }
              {
                assertion = cfg.configFile == null || builtins.substring 0 1 cfg.configFile == "/";
                message = "services.auth2api.configFile must be null or an absolute path for launchd.";
              }
            ];

            services.auth2api.settings = lib.mkDefault {
              host = "127.0.0.1";
              port = cfg.port;
              "auth-dir" = toString cfg.authDir;
            };

            system.activationScripts.auth2api.text = lib.optionalString (cfg.group == "_auth2api") ''
              if ! /usr/bin/dscl . -read /Groups/_auth2api > /dev/null 2>&1; then
                /usr/sbin/dseditgroup -o create -i ${toString cfg.gid} _auth2api
              fi
            '' + lib.optionalString (cfg.user == "_auth2api") ''
              if ! /usr/bin/dscl . -read /Users/_auth2api > /dev/null 2>&1; then
                /usr/bin/dscl . -create /Users/_auth2api
                /usr/bin/dscl . -create /Users/_auth2api UserShell /usr/bin/false
                /usr/bin/dscl . -create /Users/_auth2api RealName "auth2api daemon"
                /usr/bin/dscl . -create /Users/_auth2api NFSHomeDirectory '${cfg.stateDir}'
                /usr/bin/dscl . -create /Users/_auth2api UniqueID ${toString cfg.uid}
                /usr/bin/dscl . -create /Users/_auth2api PrimaryGroupID ${toString cfg.gid}
              fi
              /usr/sbin/dseditgroup -o edit -a _auth2api -t user _auth2api
            '' + ''
              mkdir -p '${cfg.stateDir}' '${cfg.authDir}' /var/log/auth2api
              chmod 0750 '${cfg.stateDir}' '${cfg.authDir}'
              chmod 0755 /var/log/auth2api
            '' + lib.optionalString (hasUser || hasGroup) ''
              chown ${lib.optionalString hasUser cfg.user}${lib.optionalString hasGroup ":${cfg.group}"} '${cfg.stateDir}' '${cfg.authDir}' /var/log/auth2api
            '';

            launchd.daemons.auth2api = {
              serviceConfig = {
                Label = "org.nixos.auth2api";
                ProgramArguments = [ launchScript ];
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

            makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/auth2api \
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
            nodejs_22
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
