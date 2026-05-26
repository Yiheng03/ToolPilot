"use client"

import Link from "next/link"
import { Wrench, Menu, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useState } from "react"

export function Header() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border/50 bg-card/95 backdrop-blur supports-[backdrop-filter]:bg-card/80">
      <div className="container mx-auto px-4">
        <div className="flex h-16 items-center justify-between">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-accent">
              <Wrench className="h-5 w-5 text-primary-foreground" />
            </div>
            <div className="flex flex-col">
              <span className="text-lg font-bold text-foreground">ToolPilot</span>
              <span className="text-xs text-muted-foreground -mt-1">刀具智能体平台</span>
            </div>
          </Link>

          {/* Desktop Navigation */}
          <nav className="hidden md:flex items-center gap-8">
            <Link href="#configurator" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors">
              智能配置
            </Link>
            <Link href="#features" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors">
              平台能力
            </Link>
            <Link href="/knowledge" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors">
              刀具知识库
            </Link>
            <Link href="/market" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors">
              市场预测
            </Link>
            <Link href="#" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors">
              关于我们
            </Link>
          </nav>

          {/* Desktop CTA */}
          <div className="hidden md:flex items-center gap-3">
            <Button variant="ghost" size="sm">
              登录
            </Button>
            <Button size="sm" className="bg-gradient-to-r from-primary to-accent hover:opacity-90">
              免费试用
            </Button>
          </div>

          {/* Mobile Menu Button */}
          <Button
            variant="ghost"
            size="icon"
            className="md:hidden"
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          >
            {mobileMenuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </Button>
        </div>

        {/* Mobile Menu */}
        {mobileMenuOpen && (
          <div className="md:hidden py-4 border-t border-border/50">
            <nav className="flex flex-col gap-3">
              <Link href="#configurator" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors py-2">
                智能配置
              </Link>
              <Link href="#features" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors py-2">
                平台能力
              </Link>
              <Link href="/knowledge" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors py-2">
                刀具知识库
              </Link>
              <Link href="/market" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors py-2">
                市场预测
              </Link>
              <Link href="#" className="text-sm font-medium text-muted-foreground hover:text-primary transition-colors py-2">
                关于我们
              </Link>
              <div className="flex gap-3 pt-3 border-t border-border/50">
                <Button variant="outline" size="sm" className="flex-1">
                  登录
                </Button>
                <Button size="sm" className="flex-1 bg-gradient-to-r from-primary to-accent hover:opacity-90">
                  免费试用
                </Button>
              </div>
            </nav>
          </div>
        )}
      </div>
    </header>
  )
}
