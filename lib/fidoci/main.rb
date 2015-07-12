require 'yaml'
require 'securerandom'
require 'docker'

module Fidoci
    # Main entry point for D command
    # reads configuration and provide high-level commands
    class Main

        attr_accessor :config

        # Initialize entry point
        # config_file - yml file path with configuration
        def initialize(config_file = 'd.yml')
            @config = YAML.load_file(config_file)

            Docker.options = {
                read_timeout: 3600
            }

            $stdout.sync = true
        end

        # Run command in default "exec" environment
        # ie in container build and started with exec configuration
        # args - command and arguments to pass to docker run command
        def cmd(*args)
            exec_env = env(:dev, 'dev')
            exec_env.cmd(*args)
        ensure
            exec_env.stop!
        end

        # Configured docker repository name
        # image key from YAML file
        def repository_name
            config['image']
        end

        # Create environment instance with given name
        # name - key that will be used to configure this env
        # id - unique identifier of env that will be used to tag containers and images
        def env(name, id)
            Env.new(repository_name, id.to_s, config[name.to_s])
        end

        # Clean system
        # removes all service and running containers and their images
        # and removes all images build by d
        def clean
            (config.keys - ['image']).each { |name|
                env = env(name, name)
                env.clean!
            }
        end

        # Build image and run test in it
        # tag - tag name to tag image after successful build and test
        # build_id - unique build_id to be used to identify docker images and containers
        def build(tag, build_id)
            build_id = SecureRandom.hex(10) unless build_id

            test_env = env(:build, build_id)
            test_env.clean!

            success = test_env.commands

            if success
                test_env.tag_image(tag)
                test_env.push(tag)
            end

            success
        ensure
            test_env.clean! if test_env
        end
    end
end
