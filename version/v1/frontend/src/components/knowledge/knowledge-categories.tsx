"use client"

import { useState } from "react"
import { 
  Drill, 
  CircleDot, 
  RotateCcw, 
  Target, 
  Layers, 
  Sparkles,
  ChevronRight
} from "lucide-react"
import { cn } from "@/lib/utils"

const categories = [
  {
    id: "turning",
    name: "车削刀具",
    icon: RotateCcw,
    description: "外圆车刀、内孔车刀、切槽刀、螺纹车刀",
    count: 128,
    color: "from-blue-500 to-blue-600"
  },
  {
    id: "milling",
    name: "铣削刀具",
    icon: CircleDot,
    description: "立铣刀、面铣刀、球头铣刀、T型槽铣刀",
    count: 156,
    color: "from-violet-500 to-violet-600"
  },
  {
    id: "drilling",
    name: "钻削刀具",
    icon: Drill,
    description: "麻花钻、中心钻、深孔钻、阶梯钻",
    count: 89,
    color: "from-emerald-500 to-emerald-600"
  },
  {
    id: "boring",
    name: "镗削刀具",
    icon: Target,
    description: "镗刀杆、镗刀头、精镗刀、粗镗刀",
    count: 67,
    color: "from-amber-500 to-amber-600"
  },
  {
    id: "materials",
    name: "刀具材料",
    icon: Layers,
    description: "高速钢、硬质合金、陶瓷、CBN、PCD",
    count: 45,
    color: "from-rose-500 to-rose-600"
  },
  {
    id: "coating",
    name: "涂层技术",
    icon: Sparkles,
    description: "TiN、TiAlN、AlCrN、DLC涂层",
    count: 32,
    color: "from-cyan-500 to-cyan-600"
  }
]

export function KnowledgeCategories() {
  const [activeCategory, setActiveCategory] = useState("turning")

  return (
    <section className="py-12 bg-card/50 border-y border-border/50">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between mb-8">
          <h2 className="text-xl font-semibold text-foreground">知识分类</h2>
          <button className="text-sm text-primary hover:underline flex items-center gap-1">
            查看全部 <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
          {categories.map((category) => {
            const Icon = category.icon
            const isActive = activeCategory === category.id
            
            return (
              <button
                key={category.id}
                onClick={() => setActiveCategory(category.id)}
                className={cn(
                  "group relative p-4 rounded-xl border transition-all duration-300 text-left",
                  isActive 
                    ? "bg-gradient-to-br from-primary/10 to-accent/10 border-primary/30 shadow-lg shadow-primary/10" 
                    : "bg-card border-border/50 hover:border-primary/30 hover:shadow-md"
                )}
              >
                <div className={cn(
                  "w-10 h-10 rounded-lg flex items-center justify-center mb-3 transition-all",
                  isActive 
                    ? `bg-gradient-to-br ${category.color} text-white` 
                    : "bg-muted text-muted-foreground group-hover:bg-primary/10 group-hover:text-primary"
                )}>
                  <Icon className="h-5 w-5" />
                </div>
                
                <h3 className={cn(
                  "font-medium mb-1 transition-colors",
                  isActive ? "text-primary" : "text-foreground"
                )}>
                  {category.name}
                </h3>
                
                <p className="text-xs text-muted-foreground line-clamp-2 mb-2">
                  {category.description}
                </p>
                
                <span className={cn(
                  "text-xs font-medium",
                  isActive ? "text-primary" : "text-muted-foreground"
                )}>
                  {category.count} 篇文章
                </span>
              </button>
            )
          })}
        </div>
      </div>
    </section>
  )
}
