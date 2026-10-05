# frozen_string_literal: true

require 'fileutils'
require 'rbconfig'
require 'shellwords'

root = File.expand_path('..', __dir__)
Dir.chdir(root)

# Ruby2D's mruby compiler accepts one source file. Inline project-local Ruby
# files at their original require positions; never rewrite the desktop sources.
def inline_source(path, seen = [])
  path = File.expand_path(path)
  return '' if seen.include?(path)

  seen << path
  File.readlines(path).map do |line|
    match = line.match(/^require_relative ['"](.+?)['"]\s*$/)
    if match
      dependency = File.expand_path("#{match[1]}.rb", File.dirname(path))
      "\n# Inlined from #{match[1]}\n#{inline_source(dependency, seen)}\n"
    else
      line
    end
  end.join
end

FileUtils.mkdir_p('tmp/web-source')
source_path = 'tmp/web-source/game.rb'
File.write(source_path, inline_source('main.rb'))

# Compile the browser bridge together with Emscripten's filesystem helpers.
flags = Shellwords.join(['--pre-js', File.join(root, 'web/bridge.js')])
env = { 'EMCC_CFLAGS' => [ENV['EMCC_CFLAGS'], flags].compact.join(' ') }
command = [RbConfig.ruby, '-S', 'ruby2d', 'build', '--web', '--assets', 'assets', '--template', 'web/index.html']
command << '--debug' if ARGV.include?('--debug')
abort 'Falha ao compilar a versão web.' unless system(env, *command, source_path)

FileUtils.cp('build/web/app.html', 'build/web/index.html')
File.write('build/web/.nojekyll', '')
puts 'Pronto: publique o conteúdo de build/web/ no GitHub Pages.'
