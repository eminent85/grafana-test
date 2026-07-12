package main

import rego.v1

deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("%s/%s uses a mutable latest image", [input.kind, input.metadata.name])
}

deny contains msg if {
  input.kind == "Secret"
  input.stringData
  msg := sprintf("%s/%s contains stringData; use ExternalSecret", [input.kind, input.metadata.name])
}

deny contains msg if {
  input.kind == "Ingress"
  not input.spec.tls
  msg := sprintf("Ingress/%s has no TLS configuration", [input.metadata.name])
}

