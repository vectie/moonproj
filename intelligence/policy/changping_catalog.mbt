///|
fn changping_rule(
  rule_id : String,
  phrases : Array[String],
  topic : String,
  lane : BusinessLane,
  base_score : Int,
  audience : String,
  proposed_offer : String,
  next_action : String,
) -> PolicySignalRule {
  PolicySignalRule::new(
    rule_id~,
    phrases~,
    topic~,
    lane~,
    base_score~,
    audience~,
    proposed_offer~,
    next_action~,
  ) catch {
    _ => abort("the built-in Changping policy signal catalog must be valid")
  }
}

///|
/// Seed vocabulary derived from the user's Changping planning material. It is
/// a configurable tracking catalog, not an assertion that any quoted passage
/// is authentic, current, legally binding, funded, or open for procurement.
pub fn changping_development_signal_rules() -> Array[PolicySignalRule] {
  [
    changping_rule(
      "changping.compute-node",
      [
        "算力中心", "3+N算力中心体系", "北京市级算力节点", "全市超级算力节点",
      ],
      "市级算力节点",
      Dual,
      74,
      "区级数字化主管部门、园区与算力需求企业",
      "边缘算力接入、Agent运行底座和可计量算力服务",
      "形成接入架构、资源计量、安全边界和三个月试点指标",
    ),
    changping_rule(
      "changping.advanced-energy",
      ["先进能源", "4500亿元"],
      "先进能源产业",
      B2B,
      78,
      "能源谷企业、先进能源产业链服务商",
      "能源企业智能质检、知识助手和经营分析Agent",
      "按研发、生产、供应链三类企业各访谈一家，选择高频付费问题",
    ),
    changping_rule(
      "changping.university-transfer",
      ["成果转化", "两口一园", "未来大学科技园"],
      "高校成果转化",
      Dual,
      70,
      "未来大学科技园、成果转化机构与科技企业",
      "成果需求匹配图谱、企业验证沙盒和青年人才服务",
      "建立十项成果与十家企业需求的双向验证清单",
    ),
    changping_rule(
      "changping.aigc-park",
      ["AIGC", "AIGC产业园", "千帆音乐公园"],
      "AIGC产业生态",
      B2B,
      68,
      "AIGC内容企业、园区运营方与活动主办方",
      "内容生成Agent、互动体验和合规可追溯的算力服务",
      "用一个真实活动场景验证内容生产周期、成本和版权证据链",
    ),
    changping_rule(
      "changping.youth",
      ["青年友好城市", "昌平青年"],
      "昌平青年",
      Dual,
      66,
      "青年创业者、人才服务部门与园区",
      "青年OPC孵化、人才社区运营和企业服务助手",
      "定义入驻、开办、首单和就业四项可量化转化指标",
    ),
    changping_rule(
      "changping.huitian-brain",
      [
        "回天大脑", "迭代升级‘回天大脑’", "迭代升级“回天大脑”",
      ],
      "回天大脑迭代",
      B2G,
      80,
      "回天地区治理部门与平台运营单位",
      "治理智能体、事件知识图谱和效果评估组件",
      "先梳理存量平台接口和一个低风险治理流程，提交只读验证方案",
    ),
    changping_rule(
      "changping.policy-platform",
      ["政策平台", "昌慧达"],
      "昌慧达政策服务",
      Dual,
      72,
      "政策平台运营部门与本地企业",
      "政策数据接入、企业适配解释和需求反馈闭环",
      "确认数据授权和接口边界，制作十家企业的政策匹配样例",
    ),
    changping_rule(
      "changping.company-service",
      ["企业服务", "昌相伴"],
      "昌相伴企业服务",
      Dual,
      75,
      "企业服务部门、园区运营方与入驻企业",
      "街区企业智能体和全生命周期陪伴服务",
      "选取政策申报、项目落地和经营预警三个流程做人工复核试点",
    ),
    changping_rule(
      "changping.city-governance",
      [
        "城市治理", "超大城市治理有益经验", "打造首都高质量发展的昌平样板",
      ],
      "超大城市治理样板",
      B2G,
      82,
      "区级治理部门、街道和园区管理单位",
      "可审计的街区治理智能体与量化成效看板",
      "选择一个不涉及自动执法的场景，定义基线、责任人和验收指标",
    ),
  ]
}
