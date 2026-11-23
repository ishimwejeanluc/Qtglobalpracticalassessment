{{/* NGINX config, used by configmap.yaml and as a checksum in deployment.yaml */}}
{{- define "projecthub-edge.nginxConf" -}}
upstream frontend_upstream { server {{ .Values.upstreams.frontend }}; }
upstream api_upstream      { server {{ .Values.upstreams.api }}; }

server {
    listen 8080 default_server;
    server_name _;
    server_tokens off;
    client_max_body_size 5m;

    proxy_http_version 1.1;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout    60s;

    # /api prefix preserved (proxy_pass without URI)
    location /api/ { proxy_pass http://api_upstream; }
    location /     { proxy_pass http://frontend_upstream; }

    location = /nginx-health {
        access_log off;
        return 200 "ok\n";
    }
}
{{- end }}
