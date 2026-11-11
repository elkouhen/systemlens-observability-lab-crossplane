# Affiche la clé <clé> du ConfigMap <nom> d'un rendu Kustomize lu sur l'entrée standard
# (make otel-config-validate : configurations des collecteurs de k3s-01).
# Usage : kubectl kustomize <dir> | ruby -ryaml configmap-key.rb <nom> <clé>
require 'yaml'

name, key = ARGV
YAML.load_stream($stdin.read) do |doc|
  next unless doc.is_a?(Hash) && doc['kind'] == 'ConfigMap' && doc.dig('metadata', 'name') == name

  puts doc.dig('data', key)
end
