#!/usr/bin/env ruby
# frozen_string_literal: true

# Keep Taskfile style predictable as the command surface grows. These checks are
# intentionally repo-specific: they enforce naming, flow-control, and command
# formatting conventions

require "yaml"

TASKFILES = [
  "Taskfile.yml",
  *Dir["taskfiles/*.yml"].sort
].freeze

MAX_LINE_LENGTH = 120
ALLOWED_DEPS = {
  "taskfiles/tools.yml" => ["tools", "tools:status"].freeze
}.freeze
TASK_NAMESPACE_BY_FILE = {
  "taskfiles/bootstrap.yml" => "bootstrap",
  "taskfiles/flux.yml" => "flux",
  "taskfiles/kubeconfig.yml" => "kubeconfig",
  "taskfiles/lint.yml" => "lint",
  "taskfiles/tools.yml" => "tools"
}.freeze

def load_taskfile(path, errors)
  YAML.load_file(path)
rescue Psych::SyntaxError => e
  errors << "#{path}: YAML parse error: #{e.message}"
  nil
end

def lint_lines(path, errors)
  File.readlines(path, chomp: true).each_with_index do |line, index|
    line_number = index + 1

    lint_line_length(path, line_number, line, errors)
    lint_task_call_style(path, line_number, line, errors)
    lint_shell_task_call(path, line_number, line, errors)
    lint_tools_bin_quoting(path, line_number, line, errors)
  end
end

def lint_line_length(path, line_number, line, errors)
  return unless line.length > MAX_LINE_LENGTH

  errors << "#{path}:#{line_number}: line is #{line.length} chars; max is #{MAX_LINE_LENGTH}"
end

def lint_task_call_style(path, line_number, line, errors)
  return unless line.match?(/^\s+-\s+task\s+[a-z0-9:_-]+/)

  errors << "#{path}:#{line_number}: use structured task calls, e.g. `- task: name`"
end

def lint_shell_task_call(path, line_number, line, errors)
  return unless line.match?(/^\s+-\s+task\s+/)

  errors << "#{path}:#{line_number}: use structured task calls instead of shelling out to task"
end

def lint_tools_bin_quoting(path, line_number, line, errors)
  return unless line.match?(/"\{\{\.TOOLS_BIN\}\}\/[^"]+\s[^"]+"/)

  errors << "#{path}:#{line_number}: quote only the executable path, not its arguments"
end

def lint_deps_usage(path, data, errors)
  tasks = data.fetch("tasks", {})

  tasks.each do |name, config|
    next unless config.is_a?(Hash) && config.key?("deps")
    next if allowed_deps?(path, name)

    errors << "#{path}: task #{name.inspect} uses deps; use ordered `cmds: - task:` for workflow prechecks"
  end
end

def allowed_deps?(path, task_name)
  ALLOWED_DEPS.fetch(path, []).include?(task_name)
end

def lint_includes(path, data, errors)
  return unless path == "Taskfile.yml"

  includes = data.fetch("includes", {})
  includes.each do |name, config|
    unless config.is_a?(Hash)
      errors << "#{path}: include #{name.inspect} must use long form with taskfile and flatten"
      next
    end

    expected_path = "./taskfiles/#{name}.yml"
    errors << "#{path}: include #{name.inspect} should use #{expected_path}" unless config["taskfile"] == expected_path
    errors << "#{path}: include #{name.inspect} must set flatten: true" unless config["flatten"] == true
  end
end

def lint_task_metadata(path, data, errors)
  tasks = data.fetch("tasks", {})
  namespace = TASK_NAMESPACE_BY_FILE[path]

  tasks.each do |name, config|
    next unless config.is_a?(Hash)

    errors << "#{path}: task #{name.inspect} is missing desc" unless config.key?("desc")
    next unless namespace

    next if name == namespace || name.start_with?("#{namespace}:")

    errors << "#{path}: task #{name.inspect} should use #{namespace.inspect} namespace"
  end
end

def lint_task_can_load(errors)
  return if system("task --list >/dev/null")

  errors << "Taskfile.yml: task --list failed"
end

errors = []
parsed_taskfiles = {}

TASKFILES.each do |path|
  data = load_taskfile(path, errors)
  parsed_taskfiles[path] = data if data

  lint_lines(path, errors)
end

parsed_taskfiles.each do |path, data|
  lint_includes(path, data, errors)
  lint_task_metadata(path, data, errors)
  lint_deps_usage(path, data, errors)
end

lint_task_can_load(errors)

if errors.empty?
  puts "Taskfile lint passed"
else
  warn errors.join("\n")
  exit 1
end
