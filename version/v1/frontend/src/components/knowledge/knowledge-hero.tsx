"use client"

import { Search } from "lucide-react"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"

export function KnowledgeHero() {
  return (
    <section className="relative py-16 md:py-24 overflow-hidden">
      {/* Background */}
      <div className="absolute inset-0 bg-gradient-to-br from-primary/5 via-accent/5 to-background" />
      <div className="absolute top-0 left-1/4 w-96 h-96 bg-primary/10 rounded-full blur-3xl" />
      <div className="absolute bottom-0 right-1/4 w-80 h-80 bg-accent/10 rounded-full blur-3xl" />

      <div className="container mx-auto px-4 relative z-10">
        <div className="max-w-3xl mx-auto text-center">
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 text-primary text-sm font-medium mb-6">
            <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
            专业刀具知识体系
          </div>
          
          <h1 className="text-3xl md:text-5xl font-bold text-foreground mb-6 text-balance">
            刀具知识库
          </h1>
          
          <p className="text-lg text-muted-foreground mb-8 text-pretty">
            涵盖车削、铣削、钻削、镗削等多种加工方式的专业刀具知识，
            助您深入了解刀具材料、涂层技术、几何参数与应用场景
          </p>

          {/* Search Bar */}
          <div className="flex gap-3 max-w-xl mx-auto">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-5 w-5 text-muted-foreground" />
              <Input 
                placeholder="搜索刀具类型、材料、应用场景..."
                className="pl-10 h-12 bg-card border-border/50"
              />
            </div>
            <Button className="h-12 px-6 bg-gradient-to-r from-primary to-accent hover:opacity-90">
              搜索
            </Button>
          </div>

          {/* Quick Tags */}
          <div className="flex flex-wrap justify-center gap-2 mt-6">
            {["硬质合金", "CBN刀具", "涂层技术", "切削参数", "刀具寿命", "高速切削"].map((tag) => (
              <button
                key={tag}
                className="px-3 py-1.5 text-sm rounded-full bg-card border border-border/50 text-muted-foreground hover:text-primary hover:border-primary/50 transition-colors"
              >
                {tag}
              </button>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
