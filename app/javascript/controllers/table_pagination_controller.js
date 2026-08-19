import { Controller } from "@hotwired/stimulus"

// 表格分页控制器：每页 PAGE_SIZE 条，仅控制 tbody 中行的显示/隐藏
// 与数据预警 Tab 配合使用，每个 Tab 的表格各自一个 controller 实例，翻页互不影响
export default class extends Controller {
	static targets = ["body", "prevBtn", "nextBtn", "info"]
	static values = { size: { type: Number, default: 10 } }

	connect() {
		this.currentPage = 1
		this.update()
	}

	next() {
		if (this.currentPage < this.totalPages) {
			this.currentPage += 1
			this.update()
		}
	}

	prev() {
		if (this.currentPage > 1) {
			this.currentPage -= 1
			this.update()
		}
	}

	goToFirst() {
		this.currentPage = 1
		this.update()
	}

	goToLast() {
		this.currentPage = this.totalPages
		this.update()
	}

	get rows() {
		// 只统计数据行，跳过"暂无数据"的 colspan 行
		return Array.from(this.bodyTarget.querySelectorAll("tr")).filter((tr) => {
			const td = tr.querySelector("td")
			return !(td && td.hasAttribute("colspan"))
		})
	}

	get totalPages() {
		return Math.max(1, Math.ceil(this.rows.length / this.sizeValue))
	}

	update() {
		const start = (this.currentPage - 1) * this.sizeValue
		const end = start + this.sizeValue

		this.rows.forEach((row, idx) => {
			row.style.display = idx >= start && idx < end ? "" : "none"
		})

		if (this.hasInfoTarget) {
			const total = this.rows.length
			const from = total === 0 ? 0 : start + 1
			const to = Math.min(end, total)
			this.infoTarget.textContent = `第 ${from}-${to} 条 / 共 ${total} 条 · 第 ${this.currentPage} / ${this.totalPages} 页`
		}

		if (this.hasPrevBtnTarget) {
			this.prevBtnTarget.disabled = this.currentPage === 1
			this.prevBtnTarget.classList.toggle("pg-btn-disabled", this.currentPage === 1)
		}
		if (this.hasNextBtnTarget) {
			this.nextBtnTarget.disabled = this.currentPage === this.totalPages
			this.nextBtnTarget.classList.toggle("pg-btn-disabled", this.currentPage === this.totalPages)
		}
	}
}
