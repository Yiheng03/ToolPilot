"use client"

import { Header } from "@/components/header"
import { HeroSection } from "@/components/hero-section"
import { ToolConfigurator } from "@/components/tool-configurator"
import { FeaturesSection } from "@/components/features-section"
import { Footer } from "@/components/footer"

export default function HomePage() {
  return (
    <div className="min-h-screen flex flex-col">
      <Header />
      <main className="flex-1">
        <HeroSection />
        <ToolConfigurator />
        <FeaturesSection />
      </main>
      <Footer />
    </div>
  )
}
