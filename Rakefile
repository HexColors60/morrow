require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

task :build => 'dist/index.html'
file 'dist/index.html' => FileList['src/**'] do
  sh 'npm run build'
end
CLOBBER << 'dist/'

file 'tags' => FileList['{lib,spec}/**/*.rb'] do |t|
  sh 'ctags %s' % t.sources.join(' ')
end
