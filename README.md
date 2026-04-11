# Krateo AuthN Helm Chart

This is a [Helm Chart](https://helm.sh/docs/topics/charts/) for [Krateo Snowplow](https://github.com/krateoplatformops/snowplow).

## Requirements

A Secret called 'jwt-sign-key' must exist within the same namespace where 'authn' will be deployed.
This Secret will container the key for the jwt authentication.
Here's an example of the Secret yaml:

```
apiVersion: v1
kind: Secret
metadata:
  name: jwt-sign-key
type: Opaque
stringData:
  JWT_SIGN_KEY: AbbraCadabbra
```

## How to install

```sh
helm repo add krateo https://charts.krateo.io
helm repo update krateo
helm install snowplow krateo/snowplow
```
