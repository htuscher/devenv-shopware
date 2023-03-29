{ pkgs, config, inputs, lib, ... }:

let
  cfg = config.kellerkinder;

  mappedHosts = lib.mapAttrsToList (name: value: { inherit name; }) cfg.domains;

  vhostDomains = cfg.domains ++ [ "127.0.0.1" ];
  # TODO: fix error according php_fastcgi
  vhostConfig = lib.strings.concatStrings [
    ''
      @default {
        not path ${cfg.staticFilePaths}
        not expression header_regexp('xdebug', 'Cookie', 'XDEBUG_SESSION') || query({'XDEBUG_SESSION': '*'})
      }
      @debugger {
        not path ${cfg.staticFilePaths}
        expression header_regexp('xdebug', 'Cookie', 'XDEBUG_SESSION') || query({'XDEBUG_SESSION': '*'})
      }

      root * ${cfg.documentRoot}

      encode zstd gzip

      handle /media/* {
        ${lib.strings.optionalString (cfg.fallbackMediaUrl != "") ''
        @notStatic not file
        redir @notStatic ${lib.strings.removeSuffix "/" cfg.fallbackMediaUrl}{path}
        ''}
        file_server
      }

      handle_errors {
        respond "{err.status_code} {err.status_text}"
      }

      handle {
        php_fastcgi @default unix/${config.languages.php.fpm.pools.web.socket} {
          trusted_proxies private_ranges
          index shopware.php index.php
        }

        php_fastcgi @debugger unix/${config.languages.php.fpm.pools.xdebug.socket} {
          trusted_proxies private_ranges
          index shopware.php index.php
        }

        file_server
      }

      log {
        output stderr
        format console
        level ERROR
      }
    ''
    cfg.additionalVhostConfig
  ];

  vhostConfigSSL = lib.strings.concatStrings [
    ''
      tls ${config.env.DEVENV_STATE}/mkcert/%DOMAIN%.pem ${config.env.DEVENV_STATE}/mkcert/%DOMAIN%-key.pem
    ''
    vhostConfig
  ];

  myHosts = (lib.mkMerge (lib.forEach cfg.domains (domain: {
   "${toString domain}" = "127.0.0.1";
 })));

  caddyHostConfig = (lib.mkMerge (lib.forEach vhostDomains (domain: {
    "${toString domain}:80" = lib.mkDefault {
      extraConfig = vhostConfig;
    };
    "${toString domain}:443" = lib.mkDefault {
      extraConfig = vhostConfig;
    };
  })));
in {
  config = lib.mkIf cfg.enable {
    hosts = myHosts;
    certificates = vhostDomains;

    enterShell = ''
        echo $myHosts
        echo $caddyHostConfig
      '';

    services.caddy = {
     enable = lib.mkDefault true;
     virtualHosts= caddyHostConfig;
    };
  };
}
