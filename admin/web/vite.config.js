import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,               // reachable over the tailnet during development
    proxy: { '/api': 'http://127.0.0.1:8828' },
  },
})
