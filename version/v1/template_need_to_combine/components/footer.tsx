import Link from "next/link"
import { Wrench } from "lucide-react"
import { Separator } from "@/components/ui/separator"

export function Footer() {
  return (
    <footer className="bg-card border-t border-border/50">
      <div className="container mx-auto px-4 py-12">
        <div className="grid md:grid-cols-4 gap-8">
          {/* Brand */}
          <div className="md:col-span-1">
            <Link href="/" className="flex items-center gap-2 mb-4">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-accent">
                <Wrench className="h-4 w-4 text-primary-foreground" />
              </div>
              <span className="text-lg font-bold text-foreground">ToolPilot</span>
            </Link>
            <p className="text-sm text-muted-foreground">
              机械工业刀具智能体平台，助力制造业智能升级
            </p>
          </div>

          {/* Products */}
          <div>
            <h4 className="font-semibold text-foreground mb-4">产品服务</h4>
            <ul className="space-y-2">
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  智能配置器
                </Link>
              </li>
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  刀具知识库
                </Link>
              </li>
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  在线报价
                </Link>
              </li>
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  API服务
                </Link>
              </li>
            </ul>
          </div>

          {/* Resources */}
          <div>
            <h4 className="font-semibold text-foreground mb-4">资源支持</h4>
            <ul className="space-y-2">
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  帮助中心
                </Link>
              </li>
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  技术文档
                </Link>
              </li>
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  行业报告
                </Link>
              </li>
              <li>
                <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
                  案例分享
                </Link>
              </li>
            </ul>
          </div>

          {/* Contact */}
          <div>
            <h4 className="font-semibold text-foreground mb-4">联系我们</h4>
            <ul className="space-y-2">
              <li className="text-sm text-muted-foreground">
                电话: 400-888-8888
              </li>
              <li className="text-sm text-muted-foreground">
                邮箱: support@bladewise.cn
              </li>
              <li className="text-sm text-muted-foreground">
                地址: 北京市海淀区
              </li>
            </ul>
          </div>
        </div>

        <Separator className="my-8" />

        <div className="flex flex-col md:flex-row items-center justify-between gap-4">
          <p className="text-sm text-muted-foreground">
            © 2026 ToolPilot 机械工业刀具智能体平台. 保留所有权利.
          </p>
          <div className="flex items-center gap-6">
            <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
              隐私政策
            </Link>
            <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
              服务条款
            </Link>
            <Link href="#" className="text-sm text-muted-foreground hover:text-primary transition-colors">
              京ICP备XXXXXXXX号
            </Link>
          </div>
        </div>
      </div>
    </footer>
  )
}
