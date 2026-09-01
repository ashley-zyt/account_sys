# 工作模式注册表 —— 系统内所有「工作模式」的唯一真相源
#
# 数据来自 config/work_modes.yml，负责把散落在各处的硬编码映射收敛到一处：
#   - accounts.work_type 枚举值
#   - 各工作模式对应的任务 Model（资源队列）
#   - 发布时传给机器的 task_type 标识
#   - 趋势图颜色、侧边栏分组、展示排序、简称等展示信息
#   - 是否参与自动分配 / 发布 / 手动分配 / 低库存预警
#
# 新增工作模式只需改 config/work_modes.yml，本类无需改动。
require 'yaml'

class WorkMode
  CONFIG_PATH = Rails.root.join("config", "work_modes.yml")

  ATTRS = %i[
    key name icon short_name sort enum_value task_model type_name
    trend_color sidebar_section video_field
    scheduler_assign publish manual_assign low_stock_track
  ].freeze

  attr_reader(*ATTRS)

  def initialize(hash)
    @key              = hash["key"].to_s
    @name             = hash["name"].to_s
    @icon             = hash["icon"].to_s
    @short_name       = present_or(hash["short_name"], @name)
    @sort             = hash["sort"].to_i
    @enum_value       = hash["enum_value"].to_i
    @task_model       = hash["task_model"]
    @type_name        = hash["type_name"]
    @trend_color      = hash["trend_color"]
    @sidebar_section  = hash["sidebar_section"]
    @video_field      = hash["video_field"]
    @scheduler_assign = hash.fetch("scheduler_assign", true)
    @publish          = hash.fetch("publish", true)
    @manual_assign    = hash.fetch("manual_assign", true)
    @low_stock_track  = hash.fetch("low_stock_track", false)
  end

  # 是否有对应的资源队列 Model（coze 等预留枚举值没有）
  def resource?
    task_model.present?
  end

  # 任务 Model 类（已 constantize）
  def task_model_class
    task_model.constantize if task_model.present?
  end

  # 任务 Model 对应的 has_many 关联名（如 MoveTask → :move_tasks）
  def association_name
    task_model.underscore.pluralize.to_sym
  end

  # 任务 Model 对应的 belongs_to 关联名（如 MoveTask → :move_task）
  def singular_association_name
    task_model.underscore.to_sym
  end

  # 任务日志中的类型标签（如「搬运任务」「运营任务」「剪映任务」）
  def log_label
    "#{short_name}任务"
  end

  # 任务日志页 pill 标签背景色（trend_color 的 0.1 alpha 版本）
  def pill_bg_color
    hex = trend_color.to_s.delete("#")
    return nil unless hex.length == 6
    r = hex[0..1].to_i(16)
    g = hex[2..3].to_i(16)
    b = hex[4..5].to_i(16)
    "rgba(#{r}, #{g}, #{b}, 0.1)"
  end

  # pill 标签文字色（与 trend_color 一致）
  def pill_text_color
    trend_color
  end

  # 侧边栏菜单项标签（如「搬运资源队列」）
  def sidebar_label
    "#{short_name}资源队列"
  end

  # 侧边栏菜单英文副标题（如「Move Tasks」）
  def sidebar_meta
    "#{task_model.to_s.sub('Task', '')} Tasks"
  end

  # 侧边栏菜单路由辅助方法名（如 admin_move_tasks_path）
  def route_helper
    "admin_#{key}_tasks_path"
  end

  # 侧边栏 active 判断用的 controller_path（如 admin/move_tasks）
  def controller_path
    "admin/#{key}_tasks"
  end

  private

  def present_or(value, fallback)
    (value.nil? || value.empty?) ? fallback : value
  end

  class << self
    # 全部工作模式（按展示排序）
    def all
      @all ||= load_all
    end

    # 强制重新加载配置（测试/开发热更新用）
    def reload!
      @all = nil
      @enum_mapping = nil
    end

    def find(key)
      all.find { |m| m.key == key.to_s }
    end

    # 按 Model 类反查（如 WorkMode.for_model(GrokTask)）
    def find_by_model(klass)
      all.find { |m| m.task_model == klass.name }
    end
    alias for_model find_by_model

    # 有资源队列的工作模式（不含 coze 等预留项）
    def resource_modes
      all.select(&:resource?)
    end

    # 生成 accounts.work_type 的枚举映射：{ "视频搬运" => 0, "coze" => 1, ... }
    # 按 enum_value 升序，与历史 enum 声明顺序一致
    def enum_mapping
      @enum_mapping ||= all.sort_by(&:enum_value)
                           .each_with_object({}) { |m, h| h[m.name] = m.enum_value }
    end

    # 所有任务 Model 类
    def task_models
      resource_modes.map(&:task_model_class)
    end

    # 参与自动资源分配的 Model 类（TaskScheduler）
    def scheduler_assign_modes
      resource_modes.select(&:scheduler_assign)
    end

    # 参与发布执行的 Model 类（PublishScheduler）
    def publishable_modes
      resource_modes.select(&:publish)
    end

    # 支持手动分配的映射：{ 中文名 => Model 类 }（Util）
    def manual_assign_map
      resource_modes.select(&:manual_assign)
                    .each_with_object({}) { |m, h| h[m.name] = m.task_model_class }
    end

    # 参与低库存预警的工作模式（Dashboard）
    def low_stock_track_modes
      resource_modes.select(&:low_stock_track)
    end

    private

    def load_all
      data = YAML.load_file(CONFIG_PATH)
      data.fetch("work_modes", []).map { |h| new(h) }.sort_by(&:sort)
    end
  end
end
