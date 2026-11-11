# Certificats locaux

Ce répertoire ne contient aucun certificat versionné. Il peut accueillir
localement le certificat racine PEM d'un proxy TLS d'entreprise, par exemple
`certs/zscaler-root-ca.crt`.

Exporter ensuite son chemin avant un build, l'import k3d ou le provisionnement
des VM :

```bash
export ZSCALER_CA_CERT=certs/zscaler-root-ca.crt
```

Les certificats et clés privées restent ignorés par Git. Seul ce guide est
versionné.
