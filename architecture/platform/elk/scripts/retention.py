#!/usr/bin/env python3
"""Réconcilier et contrôler les politiques ILM du lab sans exposer les secrets."""
import argparse
import base64
import copy
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['plan', 'apply', 'verify'])
    args = parser.parse_args()
    config = json.loads((Path(__file__).resolve().parent.parent / 'ilm/retention.json').read_text())
    password = os.environ.get('ELASTICSEARCH_PASSWORD') or os.environ.get('ELASTIC_PASSWORD')
    if not password:
        password = base64.b64decode(subprocess.check_output([
            os.environ.get('KUBECTL', 'kubectl'), '-n', 'elastic-stack', 'get', 'secret',
            'elasticsearch-es-elastic-user', '-o', 'jsonpath={.data.elastic}'])).decode()
    if not password:
        raise RuntimeError('Secret Elasticsearch absent.')
    url = os.environ.get('RETENTION_ELASTICSEARCH_URL', 'http://127.0.0.1:9200').rstrip('/')
    auth = 'Basic ' + base64.b64encode(('elastic:' + password).encode()).decode()

    def api(method, path, body=None, missing=False):
        request = urllib.request.Request(url + '/' + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'Authorization': auth, 'Content-Type': 'application/json'}, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404 and missing:
                return None
            # Ne jamais afficher les en-têtes d'authentification.
            raise RuntimeError(f'{method} {path}: HTTP {error.code}: {error.read().decode()}') from None

    policy = config['policy_name']
    legacy = policy + '-existing'
    policies = {policy: config['policy'], legacy: {
        'phases': {'delete': copy.deepcopy(config['policy']['phases']['delete'])}}}
    patterns = ','.join(config['patterns'])
    streams = api('GET', '_data_stream/' + patterns)['data_streams']
    excluded_streams = set(config.get('excluded_data_streams', []))
    streams = [stream for stream in streams if stream['name'] not in excluded_streams]
    if not streams:
        raise RuntimeError('Aucun data stream de télémétrie trouvé.')
    if api('GET', '_ilm/status')['operation_mode'] != 'RUNNING':
        raise RuntimeError('ILM doit être RUNNING avant application.')
    templates = api('GET', '_index_template')['index_templates']
    active_templates = {stream['template'] for stream in streams}
    relevant = [x for x in templates if x['name'] in active_templates]
    for template in relevant:
        signal = template['index_template']['index_patterns'][0].split('-')[0]
        if signal + '@custom' not in template['index_template'].get('composed_of', []):
            raise RuntimeError(f"Template sans composant commun @custom : {template['name']}")
    if args.mode == 'plan':
        print(json.dumps({'policies': policies, 'data_streams': len(streams),
                          'indices': sum(len(s['indices']) for s in streams),
                          'templates': len(relevant)}, indent=2))
        return
    if args.mode == 'apply':
        for name, body in policies.items():
            current = api('GET', '_ilm/policy/' + name, missing=True)
            if not current or current[name]['policy'] != body:
                api('PUT', '_ilm/policy/' + name, {'policy': body})
        for signal in ('logs', 'metrics', 'traces'):
            name = signal + '@custom'
            existing = api('GET', '_component_template/' + name, missing=True)
            component = existing['component_templates'][0]['component_template'] if existing else {'template': {}}
            # Elasticsearch ajoute des horodatages en lecture seule à la réponse.
            component = {key: value for key, value in component.items()
                         if key in ('template', 'version', '_meta', 'deprecated')}
            updated = copy.deepcopy(component)
            settings = updated.setdefault('template', {}).setdefault('settings', {})
            settings.pop('index.lifecycle.name', None)
            settings.pop('index.lifecycle.prefer_ilm', None)
            settings.setdefault('index', {}).setdefault('lifecycle', {}).update({'name': policy, 'prefer_ilm': 'true'})
            if updated != component:
                api('PUT', '_component_template/' + name, updated)
        # Vérifier la priorité des composants avant de migrer les indices.
        for stream in streams:
            settings = api('POST', '_index_template/_simulate_index/' + stream['name'])['template']['settings']['index']
            if settings.get('lifecycle', {}).get('name') != policy:
                raise RuntimeError('Un override de template masque la politique : ' + stream['name'])
        migrated = 0
        for stream in streams:
            write_index = stream['indices'][-1]['index_name']
            for index in stream['indices']:
                name = index['index_name']
                explanation = api('GET', name + '/_ilm/explain', missing=True)
                if explanation is None:
                    continue  # ILM a pu supprimer un ancien index pendant la réconciliation.
                state = explanation['indices'][name]
                if state.get('policy') in policies:
                    continue
                target = policy if name == write_index else legacy
                lifecycle = {'name': target, 'prefer_ilm': True}
                if target == legacy:
                    lifecycle['origination_date'] = state.get('lifecycle_date_millis', state['index_creation_date_millis'])
                if state.get('managed'):
                    result = api('POST', name + '/_ilm/remove')
                    if result.get('has_failures'):
                        raise RuntimeError('Échec du retrait de la politique : ' + name)
                api('PUT', name + '/_settings', {'index.lifecycle': lifecycle})
                migrated += 1
        print(f'ILM réconcilié : {len(streams)} data streams, {migrated} indices migrés.')
    # Vérification de la politique déclarée, des futurs indices et des indices existants.
    for name, body in policies.items():
        actual = api('GET', '_ilm/policy/' + name)[name]['policy']
        if actual != body:
            raise RuntimeError('Politique différente de la déclaration : ' + name)
    for stream in streams:
        settings = api('POST', '_index_template/_simulate_index/' + stream['name'])['template']['settings']['index']
        lifecycle = settings.get('lifecycle', {})
        if lifecycle.get('name') != policy or str(lifecycle.get('prefer_ilm')).lower() != 'true':
            raise RuntimeError('Template non conforme : ' + stream['name'])
    indices = api('GET', patterns + '/_ilm/explain')['indices']
    excluded_indices = {
        index['index_name']
        for stream in api('GET', '_data_stream/' + patterns)['data_streams']
        if stream['name'] in excluded_streams
        for index in stream['indices']
    }
    invalid = [name for name, state in indices.items()
               if name not in excluded_indices and
               (state.get('policy') not in policies or state.get('step') == 'ERROR')]
    if invalid:
        raise RuntimeError('Indices ILM non conformes : ' + ', '.join(invalid))
    print(f'ILM vérifié : {len(streams)} data streams, {len(indices)} indices, aucune erreur ILM.')


if __name__ == '__main__':
    main()
