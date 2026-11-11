# Command Center

Command Center est une interface Vue.js locale pour lancer les contrôles courants de la plateforme et simuler l'envoi d'une commande métier. Le mode actuel fournit des résultats de démonstration dans le navigateur ; il ne contacte pas Kubernetes ni les services métier.

## Pré requis

- Node.js 20 ou une version plus récente ;
- npm.

## Démarrer l'interface

Depuis la racine `architecture`, installer les dépendances puis lancer le serveur de développement :

```bash
npm --prefix apps/command-center install
npm --prefix apps/command-center run dev
```

Ouvrir ensuite l'URL affichée par Vite. Le bouton `Relancer` exécute la commande sélectionnée. Le formulaire métier affiche une réponse simulée avec un identifiant de commande.

## Construire et vérifier

```bash
make command-center-build
```

La commande doit produire `apps/command-center/dist/index.html` et le bundle JavaScript associé. Le build ne nécessite aucun secret ni accès au cluster.
