import { Controller } from "@hotwired/stimulus"

// 左侧菜单折叠控制器
//   - 分组标题点击：展开/收起该分组
//   - 顶部 ☰ 按钮：整侧边栏收窄/展开
//   - 状态通过 localStorage 持久化
export default class extends Controller {
  static targets = ["section"]

  connect() {
    this.restoreCollapsed()
    this.restoreSections()
    this.ensureActiveSectionOpen()
  }

  // 切换整侧边栏收窄状态
  toggleCollapse() {
    this.element.classList.toggle("sidebar-collapsed")
    this.persistCollapsed()
  }

  // 切换某个分组的展开/收起
  toggleSection(event) {
    // 收窄态下不处理分组折叠（分组标题已隐藏）
    if (this.element.classList.contains("sidebar-collapsed")) return

    const section = event.currentTarget.closest(".admin-sidebar-section")
    if (!section) return

    section.classList.toggle("collapsed")
    this.persistSections()
  }

  // ---- 持久化 ----

  persistCollapsed() {
    try {
      localStorage.setItem(
        "sidebar.collapsed",
        this.element.classList.contains("sidebar-collapsed") ? "true" : "false"
      )
    } catch (e) { /* localStorage 不可用时静默 */ }
  }

  persistSections() {
    const collapsed = this.sectionTargets
      .filter((s) => s.classList.contains("collapsed"))
      .map((s) => s.dataset.sectionName)
      .filter(Boolean)
    try {
      localStorage.setItem("sidebar.collapsedSections", JSON.stringify(collapsed))
    } catch (e) { /* 静默 */ }
  }

  // ---- 恢复 ----

  restoreCollapsed() {
    let collapsed = false
    try {
      collapsed = localStorage.getItem("sidebar.collapsed") === "true"
    } catch (e) { /* 静默 */ }
    this.element.classList.toggle("sidebar-collapsed", collapsed)
  }

  restoreSections() {
    let hasRecord = false
    let collapsed = []
    try {
      const raw = localStorage.getItem("sidebar.collapsedSections")
      if (raw !== null) {
        hasRecord = true
        collapsed = JSON.parse(raw) || []
      }
    } catch (e) { /* 静默 */ }

    this.sectionTargets.forEach((section) => {
      const name = section.dataset.sectionName
      // 无记录时默认折叠所有分组；有记录则按用户上次状态恢复
      const isCollapsed = hasRecord ? collapsed.includes(name) : true
      section.classList.toggle("collapsed", isCollapsed)
    })
  }

  // 即便 localStorage 记录某分组是收起的，当前 active 页所在的分组也要展开
  ensureActiveSectionOpen() {
    this.sectionTargets.forEach((section) => {
      if (section.querySelector(".admin-nav-item.active")) {
        section.classList.remove("collapsed")
      }
    })
  }
}
