# Vérifie que le Collecteur Edge de k3s-01 sert exactement les plateformes que platforms.yaml
# attribue à l'Edge otel-edge-01 (publishers, ADR-020) : liste « plateforme-environnement » de
# chaque règle transform/kafka-topic du ConfigMap otel-edge-config.
# Usage : kubectl kustomize gitops/otel-pipeline/k3s-01 | ruby -ryaml scripts/edge-platforms-check.rb gitops/otel-pipeline/platforms.yaml
require 'yaml'

edge = 'otel-edge-01'
expected = YAML.load_stream(File.read(ARGV.fetch(0))).compact
  .map { |doc| doc['spec'] }
  .select { |spec| Array(spec['publishers']).include?(edge) }
  .map { |spec| "#{spec['platform']}-#{spec['environment']}" }.sort

configmap = YAML.load_stream($stdin.read).compact
  .find { |doc| doc['kind'] == 'ConfigMap' && doc.dig('metadata', 'name') == 'otel-edge-config' }
abort 'ConfigMap otel-edge-config introuvable' unless configmap
transform = YAML.safe_load(configmap.dig('data', 'edge.yaml')).dig('processors', 'transform/kafka-topic')
lists = %w[trace metric log].map do |signal|
  statement = transform.fetch("#{signal}_statements").first.fetch('statements').join("\n")
  statement[/"\^\(([^)]*)\)\$"/, 1].to_s.split('|').sort
end

unless lists.all? { |list| list == expected }
  abort "Plateformes de l'Edge (#{lists.uniq.map { |l| l.join(',') }.join(' / ')}) " \
        "différentes de platforms.yaml (#{expected.join(',')})"
end
puts "OK      plateformes de l'Edge conformes à platforms.yaml : #{expected.join(' ')}"
