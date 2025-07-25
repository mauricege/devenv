{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.opensearch;

  settingsFormat = pkgs.formats.yaml { };
  opensearchYml = settingsFormat.generate "opensearch.yml" cfg.settings;

  loggingConfigFilename = "log4j2.properties";
  loggingConfigFile = pkgs.writeTextFile {
    name = loggingConfigFilename;
    text = cfg.logging;
  };


  startScript = pkgs.writeShellScript "opensearch-startup" ''
    set -e

    export OPENSEARCH_HOME="$OPENSEARCH_DATA"
    export OPENSEARCH_JAVA_OPTS="${toString cfg.extraJavaOptions}"
    export OPENSEARCH_PATH_CONF="$OPENSEARCH_DATA/config"
    mkdir -m 0700 -p "$OPENSEARCH_DATA"

    # Install plugins
    rm -rf "$OPENSEARCH_DATA/plugins"
    ln -sf "${cfg.package}/plugins" "$OPENSEARCH_DATA/plugins"

    rm -f "$OPENSEARCH_DATA/lib"
    ln -sf ${cfg.package}/lib "$OPENSEARCH_DATA/lib"

    rm -f "$OPENSEARCH_DATA/modules"
    ln -sf ${cfg.package}/modules "$OPENSEARCH_DATA/modules"

    # Create config dir
    mkdir -m 0700 -p "$OPENSEARCH_DATA/config"
    rm -f "$OPENSEARCH_DATA/config/opensearch.yml"

    cp ${opensearchYml} "$OPENSEARCH_DATA/config/opensearch.yml"

    rm -f "$OPENSEARCH_DATA/logging.yml"
    rm -f "$OPENSEARCH_DATA/config/${loggingConfigFilename}"
    cp ${loggingConfigFile} "$OPENSEARCH_DATA/config/${loggingConfigFilename}"

    mkdir -p "$OPENSEARCH_DATA/scripts"
    rm -f "$OPENSEARCH_DATA/config/jvm.options"

    cp ${cfg.package}/config/jvm.options "$OPENSEARCH_DATA/config/jvm.options"

    # Create log dir
    mkdir -m 0700 -p "$OPENSEARCH_DATA/logs"

    # Start it
    exec ${cfg.package}/bin/opensearch ${toString cfg.extraCmdLineOptions}
  '';

in
{
  options.services.opensearch = {
    enable = mkEnableOption "OpenSearch";

    package = lib.mkPackageOption pkgs "OpenSearch" {
      default = [ "opensearch" ];
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;

        options."network.host" = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = ''
            Which port this service should listen on.
          '';
        };

        options."cluster.name" = lib.mkOption {
          type = lib.types.str;
          default = "opensearch";
          description = ''
            The name of the cluster.
          '';
        };

        options."discovery.type" = lib.mkOption {
          type = lib.types.str;
          default = "single-node";
          description = ''
            The type of discovery to use.
          '';
        };

        options."http.port" = lib.mkOption {
          type = lib.types.port;
          default = 9200;
          description = ''
            The port to listen on for HTTP traffic.
          '';
        };

        options."transport.port" = lib.mkOption {
          type = lib.types.port;
          default = 9300;
          description = ''
            The port to listen on for transport traffic.
          '';
        };

        options."plugins.security.disabled" = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to disable the security plugin. When set to false, SSL configuration is required.
            To enable SSL, set `plugins.security.ssl.transport.keystore_filepath` or both
            `plugins.security.ssl.transport.server.pemcert_filepath` and
            `plugins.security.ssl.transport.client.pemcert_filepath`.
          '';
        };
      };

      default = { };

      description = ''
        OpenSearch configuration.
      '';
    };

    logging = lib.mkOption {
      description = "OpenSearch logging configuration.";

      default = ''
        logger.action.name = org.opensearch.action
        logger.action.level = info
        appender.console.type = Console
        appender.console.name = console
        appender.console.layout.type = PatternLayout
        appender.console.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] %marker%m%n
        rootLogger.level = info
        rootLogger.appenderRef.console.ref = console
      '';
      type = types.str;
    };

    extraCmdLineOptions = mkOption {
      description =
        "Extra command line options for the OpenSearch launcher.";
      default = [ ];
      type = types.listOf types.str;
    };

    extraJavaOptions = mkOption {
      description = "Extra command line options for Java.";
      default = [ ];
      type = types.listOf types.str;
      example = [ "-Djava.net.preferIPv4Stack=true" ];
    };
  };

  config = mkIf cfg.enable {
    env.OPENSEARCH_DATA = config.env.DEVENV_STATE + "/opensearch";

    processes.opensearch = {
      exec = "${startScript}";

      process-compose = {
        readiness_probe = {
          exec.command = "${pkgs.curl}/bin/curl -f -k http://${cfg.settings."network.host"}:${toString cfg.settings."http.port"}";
          initial_delay_seconds = 2;
          period_seconds = 10;
          timeout_seconds = 2;
          success_threshold = 1;
          failure_threshold = 5;
        };

        availability.restart = "on_failure";
      };
    };
  };
}
