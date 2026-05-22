"use client"

import { Card, CardContent } from "@/components/ui/card"
import { 
  Brain, 
  Database, 
  Zap, 
  Shield, 
  BarChart3, 
  MessagesSquare 
} from "lucide-react"

const features = [
  {
    icon: Brain,
    title: "AI智能推荐",
    description: "基于机器学习算法，分析海量刀具数据，精准匹配您的加工需求"
  },
  {
    icon: Database,
    title: "专业知识库",
    description: "涵盖500+刀具类型，50+行业应用场景的专业数据库支撑"
  },
  {
    icon: Zap,
    title: "即时响应",
    description: "秒级响应生成推荐方案，大幅提升选型效率"
  },
  {
    icon: Shield,
    title: "质量保障",
    description: "严格的供应商筛选机制，确保刀具品质可靠"
  },
  {
    icon: BarChart3,
    title: "数据分析",
    description: "提供刀具使用数据分析，优化加工参数建议"
  },
  {
    icon: MessagesSquare,
    title: "专家支持",
    description: "7×24小时在线技术支持，解答您的刀具应用问题"
  }
]

export function FeaturesSection() {
  return (
    <section id="features" className="py-20">
      <div className="container mx-auto px-4">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            平台核心能力
          </h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            依托机械工业大模型，为您提供全方位的刀具智能服务
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6 max-w-6xl mx-auto">
          {features.map((feature, index) => (
            <Card 
              key={index} 
              className="group hover:shadow-lg transition-all duration-300 border-border/50 hover:border-primary/30"
            >
              <CardContent className="pt-6">
                <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-primary/10 to-accent/10 flex items-center justify-center mb-4 group-hover:from-primary/20 group-hover:to-accent/20 transition-colors">
                  <feature.icon className="h-6 w-6 text-primary" />
                </div>
                <h3 className="text-lg font-semibold text-foreground mb-2">
                  {feature.title}
                </h3>
                <p className="text-sm text-muted-foreground">
                  {feature.description}
                </p>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  )
}
