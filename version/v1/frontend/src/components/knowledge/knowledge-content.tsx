"use client"

import { useState } from "react"
import { 
  BookOpen, 
  Clock, 
  Eye, 
  Star, 
  ChevronRight,
  Filter,
  TrendingUp,
  Bookmark
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { cn } from "@/lib/utils"

// 刀具知识文章数据
const articles = [
  {
    id: 1,
    title: "硬质合金刀具材料选择指南",
    description: "深入解析硬质合金的成分、性能特点及适用场景，帮助您为不同加工需求选择最合适的刀具材料。",
    category: "刀具材料",
    tags: ["硬质合金", "WC-Co", "晶粒度"],
    readTime: "8 分钟",
    views: 3256,
    rating: 4.9,
    featured: true,
    image: "bg-gradient-to-br from-blue-500/20 to-violet-500/20"
  },
  {
    id: 2,
    title: "TiAlN涂层技术及其应用",
    description: "介绍TiAlN涂层的制备工艺、性能优势，以及在高温、高速切削中的应用实例。",
    category: "涂层技术",
    tags: ["TiAlN", "PVD", "高温切削"],
    readTime: "6 分钟",
    views: 2187,
    rating: 4.8,
    featured: true,
    image: "bg-gradient-to-br from-violet-500/20 to-purple-500/20"
  },
  {
    id: 3,
    title: "车削加工切削参数优化",
    description: "详细讲解车削加工中切削速度、进给量、切削深度的计算方法与优化策略。",
    category: "车削刀具",
    tags: ["切削参数", "表面质量", "刀具寿命"],
    readTime: "10 分钟",
    views: 4521,
    rating: 4.9,
    featured: false,
    image: "bg-gradient-to-br from-emerald-500/20 to-teal-500/20"
  },
  {
    id: 4,
    title: "CBN刀具在淬硬钢加工中的应用",
    description: "探讨CBN（立方氮化硼）刀具的特性及在硬车削、精密加工中的优势与注意事项。",
    category: "刀具材料",
    tags: ["CBN", "硬车削", "淬硬钢"],
    readTime: "7 分钟",
    views: 1893,
    rating: 4.7,
    featured: false,
    image: "bg-gradient-to-br from-amber-500/20 to-orange-500/20"
  },
  {
    id: 5,
    title: "高效铣削策略与刀具选择",
    description: "介绍高速铣削、插铣、螺旋铣等高效铣削策略，以及配套刀具的选型要点。",
    category: "铣削刀具",
    tags: ["高速铣削", "刀具路径", "切削效率"],
    readTime: "12 分钟",
    views: 3012,
    rating: 4.8,
    featured: false,
    image: "bg-gradient-to-br from-rose-500/20 to-pink-500/20"
  },
  {
    id: 6,
    title: "深孔钻削技术要点",
    description: "分析深孔加工的技术难点，介绍枪钻、BTA钻等深孔钻具的特点与使用技巧。",
    category: "钻削刀具",
    tags: ["深孔钻", "排屑", "冷却"],
    readTime: "9 分钟",
    views: 1567,
    rating: 4.6,
    featured: false,
    image: "bg-gradient-to-br from-cyan-500/20 to-sky-500/20"
  }
]

// 刀具类型数据
const toolTypes = [
  {
    id: 1,
    name: "外圆车刀",
    material: "硬质合金 YT15",
    application: "普通钢、合金钢外圆加工",
    specs: {
      angle: "主偏角 93°",
      radius: "刀尖圆弧 0.4-1.2mm",
      insert: "CNMG120408"
    },
    parameters: {
      speed: "150-300 m/min",
      feed: "0.15-0.4 mm/r",
      depth: "0.5-4 mm"
    }
  },
  {
    id: 2,
    name: "立铣刀",
    material: "整体硬质合金",
    application: "平面、轮廓、槽型铣削加工",
    specs: {
      diameter: "直径 6-25mm",
      flutes: "4刃",
      helix: "螺旋角 35-45°"
    },
    parameters: {
      speed: "80-200 m/min",
      feed: "0.05-0.15 mm/齿",
      depth: "0.5-1.5D"
    }
  },
  {
    id: 3,
    name: "麻花钻",
    material: "高速钢 M2/M35",
    application: "通用孔加工",
    specs: {
      diameter: "直径 1-32mm",
      angle: "顶角 118-135°",
      helix: "螺旋角 25-35°"
    },
    parameters: {
      speed: "20-50 m/min",
      feed: "0.1-0.3 mm/r",
      depth: "3-5D"
    }
  },
  {
    id: 4,
    name: "面铣刀",
    material: "可转位硬质合金",
    application: "大平面高效铣削加工",
    specs: {
      diameter: "直径 50-200mm",
      inserts: "6-12刀片",
      angle: "主偏角 45-90°"
    },
    parameters: {
      speed: "120-250 m/min",
      feed: "0.1-0.25 mm/齿",
      depth: "1-6 mm"
    }
  }
]

// 常见问题数据
const faqs = [
  {
    question: "如何选择适合的刀具材料？",
    answer: "刀具材料选择应考虑：1）工件材料硬度和韧性；2）加工方式（连续/断续切削）；3）切削速度要求；4）表面质量要求；5）成本预算。一般建议：加工钢件优先考虑硬质合金涂层刀具；加工铸铁可选用陶瓷刀具；加工淬硬钢建议CBN刀具。"
  },
  {
    question: "刀具涂层有什么作用？",
    answer: "刀具涂层的主要作用：1）提高表面硬度，增强耐磨性；2）降低摩擦系数，减少切削热；3）形成热障层，保护基体材料；4）提高抗氧化性能。常用涂层包括TiN（金色）、TiAlN（紫灰色）、AlCrN（灰色）等。"
  },
  {
    question: "如何延长刀具使用寿命？",
    answer: "延长刀具寿命的方法：1）选择合适的切削参数，避免过高的切削速度和进给量；2）保证充足的冷却润滑；3）保持刀具和工件装夹刚性；4）定期检查刀具磨损情况并及时更换；5）避免断续切削时的冲击。"
  },
  {
    question: "什么情况下需要使用涂层刀具？",
    answer: "建议使用涂层刀具的场景：1）高速切削加工；2）干式或微量润滑加工；3）加工难加工材料（不锈钢、钛合金等）；4）对刀具寿命有较高要求；5）批量生产降低刀具成本。"
  }
]

function ArticleCard({ article }: { article: typeof articles[0] }) {
  return (
    <div className={cn(
      "group relative rounded-xl border border-border/50 bg-card overflow-hidden transition-all duration-300 hover:shadow-lg hover:border-primary/30",
      article.featured && "md:col-span-2"
    )}>
      <div className={cn("h-32 md:h-40", article.image)} />
      
      <div className="p-5">
        <div className="flex items-center gap-2 mb-3">
          <Badge variant="secondary" className="text-xs">
            {article.category}
          </Badge>
          {article.featured && (
            <Badge className="text-xs bg-gradient-to-r from-primary to-accent text-white border-0">
              精选
            </Badge>
          )}
        </div>
        
        <h3 className="font-semibold text-foreground mb-2 group-hover:text-primary transition-colors">
          {article.title}
        </h3>
        
        <p className="text-sm text-muted-foreground mb-4 line-clamp-2">
          {article.description}
        </p>
        
        <div className="flex flex-wrap gap-1.5 mb-4">
          {article.tags.map((tag) => (
            <span key={tag} className="text-xs px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
              {tag}
            </span>
          ))}
        </div>
        
        <div className="flex items-center justify-between text-xs text-muted-foreground pt-4 border-t border-border/50">
          <div className="flex items-center gap-4">
            <span className="flex items-center gap-1">
              <Clock className="h-3.5 w-3.5" />
              {article.readTime}
            </span>
            <span className="flex items-center gap-1">
              <Eye className="h-3.5 w-3.5" />
              {article.views.toLocaleString()}
            </span>
          </div>
          <span className="flex items-center gap-1 text-amber-500">
            <Star className="h-3.5 w-3.5 fill-current" />
            {article.rating}
          </span>
        </div>
      </div>
    </div>
  )
}

function ToolTypeCard({ tool }: { tool: typeof toolTypes[0] }) {
  return (
    <div className="group p-5 rounded-xl border border-border/50 bg-card hover:shadow-lg hover:border-primary/30 transition-all duration-300">
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="font-semibold text-foreground group-hover:text-primary transition-colors">
            {tool.name}
          </h3>
          <p className="text-sm text-muted-foreground mt-1">{tool.material}</p>
        </div>
        <Bookmark className="h-5 w-5 text-muted-foreground hover:text-primary cursor-pointer transition-colors" />
      </div>
      
      <p className="text-sm text-muted-foreground mb-4">{tool.application}</p>
      
      <div className="space-y-3">
        <div className="p-3 rounded-lg bg-muted/50">
          <p className="text-xs font-medium text-foreground mb-2">几何规格</p>
          <div className="grid grid-cols-1 gap-1 text-xs text-muted-foreground">
            {Object.values(tool.specs).map((spec, i) => (
              <span key={i}>{spec}</span>
            ))}
          </div>
        </div>
        
        <div className="p-3 rounded-lg bg-primary/5 border border-primary/10">
          <p className="text-xs font-medium text-primary mb-2">推荐切削参数</p>
          <div className="grid grid-cols-1 gap-1 text-xs text-muted-foreground">
            <span>切削速度: {tool.parameters.speed}</span>
            <span>进给量: {tool.parameters.feed}</span>
            <span>切削深度: {tool.parameters.depth}</span>
          </div>
        </div>
      </div>
      
      <Button variant="ghost" className="w-full mt-4 text-primary hover:bg-primary/10">
        查看详情 <ChevronRight className="h-4 w-4 ml-1" />
      </Button>
    </div>
  )
}

function FAQItem({ faq, index }: { faq: typeof faqs[0], index: number }) {
  const [isOpen, setIsOpen] = useState(index === 0)
  
  return (
    <div className="border border-border/50 rounded-xl overflow-hidden">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between p-5 text-left bg-card hover:bg-muted/50 transition-colors"
      >
        <span className="font-medium text-foreground">{faq.question}</span>
        <ChevronRight className={cn(
          "h-5 w-5 text-muted-foreground transition-transform",
          isOpen && "rotate-90"
        )} />
      </button>
      {isOpen && (
        <div className="px-5 pb-5 pt-0 bg-card">
          <p className="text-sm text-muted-foreground leading-relaxed">
            {faq.answer}
          </p>
        </div>
      )}
    </div>
  )
}

export function KnowledgeContent() {
  return (
    <section className="py-12 md:py-16">
      <div className="container mx-auto px-4">
        <Tabs defaultValue="articles" className="space-y-8">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <TabsList className="bg-muted/50 p-1">
              <TabsTrigger value="articles" className="gap-2">
                <BookOpen className="h-4 w-4" />
                技术文章
              </TabsTrigger>
              <TabsTrigger value="tools" className="gap-2">
                <Filter className="h-4 w-4" />
                刀具手册
              </TabsTrigger>
              <TabsTrigger value="faq" className="gap-2">
                <TrendingUp className="h-4 w-4" />
                常见问题
              </TabsTrigger>
            </TabsList>
            
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <span>排序:</span>
              <select className="bg-transparent border-none text-foreground font-medium focus:outline-none cursor-pointer">
                <option>最新发布</option>
                <option>最多阅读</option>
                <option>最高评分</option>
              </select>
            </div>
          </div>

          <TabsContent value="articles" className="mt-0">
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
              {articles.map((article) => (
                <ArticleCard key={article.id} article={article} />
              ))}
            </div>
            
            <div className="flex justify-center mt-10">
              <Button variant="outline" className="gap-2">
                加载更多文章
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </TabsContent>

          <TabsContent value="tools" className="mt-0">
            <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
              {toolTypes.map((tool) => (
                <ToolTypeCard key={tool.id} tool={tool} />
              ))}
            </div>
            
            <div className="flex justify-center mt-10">
              <Button variant="outline" className="gap-2">
                浏览更多刀具
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </TabsContent>

          <TabsContent value="faq" className="mt-0">
            <div className="max-w-3xl mx-auto space-y-4">
              {faqs.map((faq, index) => (
                <FAQItem key={index} faq={faq} index={index} />
              ))}
            </div>
            
            <div className="max-w-3xl mx-auto mt-8 p-6 rounded-xl bg-gradient-to-br from-primary/10 to-accent/10 border border-primary/20 text-center">
              <h3 className="font-semibold text-foreground mb-2">没有找到您需要的答案？</h3>
              <p className="text-sm text-muted-foreground mb-4">
                联系我们的技术专家，获取一对一的专业咨询服务
              </p>
              <Button className="bg-gradient-to-r from-primary to-accent hover:opacity-90">
                咨询专家
              </Button>
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </section>
  )
}
