/** @type {import('next').NextConfig} */
const nextConfig = {
  allowedDevOrigins: ["127.0.0.1", "10.7.29.17"],
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  async rewrites() {
    return [
      {
        source: "/api/market/:path*",
        destination: "http://127.0.0.1:8765/api/market/:path*",
      },
    ]
  },
}

export default nextConfig
