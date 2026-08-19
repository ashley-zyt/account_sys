import { Controller } from "@hotwired/stimulus"

// 右侧抽屉：点击「详情」「发文数据」等链接时滑出，异步加载账号详情
// 用法：
//   触发元素：data-action="drawer#open" data-drawer-id-param="123" data-drawer-tab-param="overview"
//   抽屉容器：data-controller="drawer" data-drawer-url-value="/admin/data_alerts/account"
//   抽屉内 Tab 按钮：data-drawer-target="tab" data-drawer-tab-name="overview" data-action="drawer#switchTab"
//   内容面板（异步加载的 HTML 中）：data-drawer-panel="overview"
export default class extends Controller {
	static targets = ["drawer", "content", "backdrop", "tab"]
	static values = { url: String }

	connect() {
		this.currentAccountId = null
		this.currentTab = "overview"
		this._keydownHandler = (e) => { if (e.key === "Escape") this.close() }
		document.addEventListener("keydown", this._keydownHandler)
	}

	disconnect() {
		document.removeEventListener("keydown", this._keydownHandler)
		document.body.style.overflow = ""
	}

	open(event) {
		const id = event.params.id
		const tab = event.params.tab || "overview"
		this.currentAccountId = id
		this.currentTab = tab

		// 高亮对应 Tab 按钮
		this.tabTargets.forEach((el) => {
			el.classList.toggle("drawer-tab-active", el.dataset.drawerTabName === tab)
		})

		// 显示抽屉 + 遮罩
		this.drawerTarget.classList.add("drawer-open")
		this.backdropTarget.classList.add("drawer-backdrop-visible")
		document.body.style.overflow = "hidden"

		// 加载内容
		this.loadContent(id)
	}

	close() {
		this.drawerTarget.classList.remove("drawer-open")
		this.backdropTarget.classList.remove("drawer-backdrop-visible")
		document.body.style.overflow = ""
	}

	switchTab(event) {
		const tabName = event.params.name
		this._activateTab(tabName)
	}

	_activateTab(tabName) {
		this.currentTab = tabName
		this.tabTargets.forEach((el) => {
			el.classList.toggle("drawer-tab-active", el.dataset.drawerTabName === tabName)
		})
		this.contentTarget.querySelectorAll("[data-drawer-panel]").forEach((panel) => {
			panel.style.display = panel.dataset.drawerPanel === tabName ? "" : "none"
		})
	}

	async loadContent(accountId) {
		this.contentTarget.innerHTML = '<div style="padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px;">加载中...</div>'
		try {
			const url = new URL(this.urlValue, window.location.origin)
			url.searchParams.set("id", accountId)
			const resp = await fetch(url.toString(), {
				headers: { "Accept": "text/html" },
				credentials: "same-origin"
			})
			if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
			const html = await resp.text()
			this.contentTarget.innerHTML = html
			// 初始显示当前 Tab 的面板
			this._activateTab(this.currentTab)
		} catch (e) {
			this.contentTarget.innerHTML = `<div style="padding: 40px 20px; text-align: center; color: var(--danger); font-size: 13px;">加载失败：${e.message}</div>`
		}
	}
}
