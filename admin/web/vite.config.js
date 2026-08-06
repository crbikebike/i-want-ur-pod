import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,               // reachable over the tailnet during development
    // The tailnet machine name, so a phone browsing http://hfab:5173 clears
    // vite's host check. Add the bare IP form too; it is always allowed.
    allowedHosts: ['hfab'],
    // The API binds to the tailscale IP (admin/api/main.py: tailscale_ip()),
    // not loopback -- a 127.0.0.1 target dials a port nothing listens on, and
    // the name `hfab` is this machine's own hostname, which /etc/hosts sends
    // to 127.0.1.1. Only the tailscale IP itself reaches the API from here.
    proxy: { '/api': 'http://100.117.245.23:8828' },
  },
})
