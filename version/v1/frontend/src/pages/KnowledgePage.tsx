"use client"

import { Header } from "@/components/header"
import { Footer } from "@/components/footer"
import { KnowledgeHero } from "@/components/knowledge/knowledge-hero"
import { KnowledgeCategories } from "@/components/knowledge/knowledge-categories"
import { KnowledgeContent } from "@/components/knowledge/knowledge-content"

export default function KnowledgePage() {
  return (
    <div className="min-h-screen flex flex-col">
      <Header />
      <main className="flex-1">
        <KnowledgeHero />
        <KnowledgeCategories />
        <KnowledgeContent />
      </main>
      <Footer />
    </div>
  )
}
