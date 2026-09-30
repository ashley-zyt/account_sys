# 金融免责声明后处理：数字货币主题的发文，给标题/描述追加免责声明。
#
# 规则：
#   - 仅 theme == '数字货币' 时生效
#   - 免责声明：For informational purposes only. Not financial advice.
#   - 追加位置：hashtag（#）之前；无 hashtag 则追加到末尾；已含则跳过（幂等）
module FinancialDisclaimer
  TEXT = "For informational purposes only. Not financial advice."
  CRYPTO_THEME = '数字货币'

  module_function

  # 该主题是否需要追加免责声明
  def applies_to?(theme)
    theme.to_s == CRYPTO_THEME
  end

  # 给一段文本追加免责声明（hashtag 前；无 hashtag 末尾；幂等）
  def append(text)
    base = text.to_s.strip
    return base if base.blank? || base.include?(TEXT)
    idx = base.index('#')
    idx ? base.insert(idx, "#{TEXT} ") : "#{base} #{TEXT}"
  end
end
