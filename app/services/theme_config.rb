# app/services/theme_config.rb
# 对标账号匹配 + 标题池，统一读 Theme 表（后台可自助维护，不再依赖 theme_config.yml）。

class ThemeConfig
	class << self
		# 根据来源账号主页链接匹配主题。
		# 读 Theme 表（后台可自助维护对标账号）。
		def match_theme(source_url)
			return nil if source_url.blank?

			Theme.where.not(source_accounts: [nil, '']).find_each do |theme|
				theme.source_accounts_array.each do |url|
					return theme.name if source_url.include?(url)
				end
			end
			nil
		end

		# 从主题标题池中随机选择一个标题。
		# 读 Theme 表的 titles。
		def random_title(theme_name)
			theme = Theme.find_by(name: theme_name)
			return nil unless theme

			theme.titles_array.sample
		end
	end
end
