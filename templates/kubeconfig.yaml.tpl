apiVersion: v1
kind: Config
clusters:
- name: ${cluster_name}
  cluster:
    server: ${endpoint}
    certificate-authority-data: ${cert_data}
contexts:
- name: ${cluster_name}-context
  context:
    cluster: ${cluster_name}
    user: ${cluster_name}-user
current-context: ${cluster_name}-context
users:
- name: ${cluster_name}-user
  user:
    token: ${token}
