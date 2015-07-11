require_relative 'lib/fidoci/version'

Gem::Specification.new do |s|
  s.name        = 'fidoci'
  s.version     = Fidoci::VERSION
  s.licenses    = ['MIT']
  s.summary     = "Finally Docker CI"
  s.description = "Simple tool around docker-compose to enable dockerized dev-2-test-2-production workflow"
  s.authors     = ["Lukas Dolezal"]
  s.email       = 'lukas@dolezalu.cz'
  s.files       = ["lib/fidoci.rb", "lib/fidoci/env.rb", "lib/fidoci/main.rb"]
  s.executables << "d"
  s.homepage    = 'https://github.com/DocX/fidoci'

  s.add_runtime_dependency "docker-api"
end