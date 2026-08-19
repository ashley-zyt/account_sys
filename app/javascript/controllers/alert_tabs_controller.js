import { Controller } from "@hotwired/stimulus"

// 数据预警页 Tab 切换：顶部指标卡作为 Tab，点击切换下方表格
// 默认激活：URL hash → 第一个有预警的 Tab → 第一个 Tab
export default class extends Controller {
	static targets = ["tab", "panel"]

	connect() {
		const fromHash = window.location.hash.replace("#", "")
		const names = this.tabTargets.map((tab) => tab.dataset.alertTabsName)
		const firstAlerted = this.tabTargets.find((tab) => tab.dataset.alertTabsHasAlert === "true")
		const initial = names.includes(fromHash) ? fromHash : (firstAlerted && firstAlerted.dataset.alertTabsName) || names[0]
		this.show(initial, false)
	}

	select(event) {
		this.show(event.params.name, true)
	}

	show(name, updateHash) {
		const matched = this.tabTargets.some((tab) => tab.dataset.alertTabsName === name)
		if (!matched) return

		this.tabTargets.forEach((tab) => {
			tab.classList.toggle("alert-tab-active", tab.dataset.alertTabsName === name)
		})
		this.panelTargets.forEach((panel) => {
			panel.classList.toggle("alert-panel-hidden", panel.dataset.alertTabsName !== name)
		})
		if (updateHash) history.replaceState(null, "", `#${name}`)
	}
}
