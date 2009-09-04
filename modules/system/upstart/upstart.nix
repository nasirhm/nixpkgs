{config, pkgs, ...}:

with pkgs.lib;

let

  # From a job description, generate an Upstart job file.
  makeJob = job@{buildHook ? "", ...}:

    let

      jobText = if job.job != "" then job.job else
        ''
          # Upstart job `${job.name}'.  This is a generated file.  Do not edit.
        
          description "${job.description}"

          ${if isList job.startOn then
              # This is a hack to support or-dependencies on Upstart 0.3.
              concatMapStrings (x: "start on ${x}\n") job.startOn
            else if job.startOn != "" then
              "start on ${job.startOn}"
            else ""
          }
          
          ${if job.stopOn != "" then "stop on ${job.stopOn}" else ""}

          ${concatMapStrings (n: "env ${n}=${getAttr n job.environment}\n") (attrNames job.environment)}
          
          ${if job.preStart != "" then ''
            start script
              ${job.preStart}
            end script
          '' else ""}
          
          ${if job.script != "" && job.exec != "" then
              abort "Job ${job.name} has both a `script' and `exec' attribute."
            else if job.script != "" then
              ''
                script
                  ${job.script}
                end script
              ''
            else if job.exec != "" then
              ''
                exec ${job.exec}
              ''
            else
              # Simulate jobs without a main process (which Upstart 0.3
              # doesn't support) using a semi-infinite sleep.
              ''
                exec sleep 1e100
              ''
          }

          ${if job.respawn && !job.task then "respawn" else ""}

          ${if job.postStop != "" then ''
            stop script
              ${job.postStop}
            end script
          '' else ""}

          ${job.extraConfig}
        '';

    in
      pkgs.runCommand ("upstart-" + job.name)
        { inherit buildHook; inherit jobText; }
        ''
          eval "$buildHook"
          ensureDir $out/etc/event.d
          echo "$jobText" > $out/etc/event.d/${job.name}
        '';

        
  jobs =
    [pkgs.upstart] # for the built-in logd job
    ++ map makeJob (config.jobs ++ config.services.extraJobs);
  
  # Create an etc/event.d directory containing symlinks to the
  # specified list of Upstart job files.
  jobsDir = pkgs.runCommand "upstart-jobs" {inherit jobs;}
    ''
      ensureDir $out/etc/event.d
      for i in $jobs; do
        if ln -s $i . ; then
          if test -d $i; then
            ln -s $i/etc/event.d/* $out/etc/event.d/
          fi
        else
          echo Duplicate entry: $i;
        fi;
      done
    ''; # */

in
  
{

  ###### interface
  
  options = {
  
    jobs = mkOption {
      default = [];
      description = ''
        This option defines the system jobs started and managed by the
        Upstart daemon.
      '';

      type = types.list types.optionSet;

      options = {

        name = mkOption {
          type = types.string;
          example = "sshd";
          description = ''
            Name of the Upstart job.
          '';
        };

        job = mkOption {
          default = "";
          type = types.string;
          example =
            ''
              description "nc"
              start on started network-interfaces
              respawn
              env PATH=/var/run/current-system/sw/bin
              exec sh -c "echo 'hello world' | ${pkgs.netcat}/bin/nc -l -p 9000"
            '';
          description = ''
            Contents of the Upstart job.
          '';
        };

        buildHook = mkOption {
          type = types.string;
          default = "true";
          description = ''
            Command run while building the Upstart job.  Can be used
            to perform simple regression tests (e.g., the Apache
            Upstart job uses it to check the syntax of the generated
            <filename>httpd.conf</filename>.
          '';
        };

        description = mkOption {
          type = types.string;
          default = "(no description given)";
          description = ''
            A short description of this job.
          '';
        };

        startOn = mkOption {
          # !!! Re-enable this once we're on Upstart >= 0.6.
          #type = types.string; 
          default = "";
          description = ''
            The Upstart event that triggers this job to be started.
            If empty, the job will not start automatically.
          '';
        };

        stopOn = mkOption {
          type = types.string;
          default = "shutdown";
          description = ''
            The Upstart event that triggers this job to be stopped.
          '';
        };

        preStart = mkOption {
          type = types.string;
          default = "";
          description = ''
            Shell commands executed before the job is started
            (i.e. before the job's main process is started).
          '';
        };

        postStop = mkOption {
          type = types.string;
          default = "";
          description = ''
            Shell commands executed after the job has stopped
            (i.e. after the job's main process has terminated).
          '';
        };

        exec = mkOption {
          type = types.string;
          default = "";
          description = ''
            Command to start the job's main process.  If empty, the
            job has no main process, but can still have pre/post-start
            and pre/post-stop scripts, and is considered "running"
            until it is stopped.
          '';
        };

        script = mkOption {
          type = types.string;
          default = "";
          description = ''
            Shell commands executed as the job's main process.  Can be
            specified instead of the <varname>exec</varname> attribute.
          '';
        };

        respawn = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to restart the job automatically if its process
            ends unexpectedly.
          '';
        };

        task = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether this job is a task rather than a service.  Tasks
            are executed only once, while services are restarted when
            they exit.
          '';
        };

        environment = mkOption {
          type = types.attrs;
          default = {};
          example = { PATH = "/foo/bar/bin"; LANG = "nl_NL.UTF-8"; };
          description = ''
            Environment variables passed to the job's processes.
          '';
        };

        extraConfig = mkOption {
          type = types.string;
          default = "";
          example = "limit nofile 4096 4096";
          description = ''
            Additional Upstart stanzas not otherwise supported.
          '';
        };

      };
      
    };

    services.extraJobs = mkOption {
      default = [];
      description = ''
        Obsolete - don't use.
      '';
    };

    tests.upstartJobs = mkOption {
      internal = true;
      default = {};
      description = ''
        Make it easier to build individual Upstart jobs. (e.g.,
        <command>nix-build /etc/nixos/nixos -A
        tests.upstartJobs.xserver</command>).
      '';
    };
    
  };


  ###### implementation
  
  config = {

    environment.etc =
      [ { # The Upstart events defined above.
          source = "${jobsDir}/etc/event.d";
          target = "event.d";
        }
      ];

    # see test/test-upstart-job.sh (!!! check whether this still works)
    tests.upstartJobs = { recurseForDerivations = true; } //
      builtins.listToAttrs (map (job:
        { name = if job ? jobName then job.jobName else job.name; value = job; }
      ) jobs);
  
  };

}
