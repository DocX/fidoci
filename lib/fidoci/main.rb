require 'yaml'

module Fidoci
    # Main entry point for D command
    # reads configuration and provide high-level commands
    class Main

        attr_accessor :config

        # Initialize entry point
        # config_file - yml file path with configuration
        def initialize(config_file = 'd.yml')
            @config = YAML.load_file(config_file)
            puts @config['image']
        end

        # Run command in default "exec" environment
        # ie in container build and started with exec configuration
        # args - command and arguments to pass to docker run command
        def cmd(*args)
            env(:exec).cmd(*args)
        end

        # Configured docker repository name
        # image key from YAML file
        def repository_name
            config['image']
        end

        # Create environment instance with given name
        # name - key that will be used to configure this env
        def env(name)
            Env.new(repository_name, name.to_s, config[name.to_s])
        end

        # Clean system
        # removes all service and running containers and their images
        # and removes all images build by d
        def clean
            system 'docker-compose kill'
            system 'docker-compose rm -f'

            (config.keys - ['image']).each { |name|
                env = env(name)
                system "docker rmi -f #{env.image_name}"
            }
        end

        # Build image and run test in it
        # tag - tag name to tag image after successful build and test
        # do_clean - if true, will do clean after build (whether successful or not)
        def build(tag, do_clean = false)
            test_env = env(:test)
            success = test_env.commands

            if success
                system "docker tag #{test_env.image_name} #{repository_name}:#{tag}"
            end

            clean if do_clean
            success
        end
    end
end
