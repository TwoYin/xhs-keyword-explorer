# XHS Keyword Explorer - 完整工作流

## Phase 1: 种子关键词准备

### 1.1 确定业务定位

明确你要推广的产品/服务的核心属性：
- **地域**：城市、街道、商圈
- **品类**：产品类型、细分品类
- **场景**：消费场景、用户场景
- **需求**：用户痛点、搜索意图
- **竞品**：直接竞品、间接竞品

### 1.2 生成分层关键词

建议按以下六层结构生成初始词库（50-80个）：

| 层级 | 示例 | 数量 |
|---|---|---|
| 地域大词 | `城市 + 品类` | 8-12 |
| 街道精准词 | `街道 + 品类` | 5-8 |
| 场景需求词 | `城市 + 场景` | 10-15 |
| 品类细分词 | `城市 + 细分品类` | 8-12 |
| 长尾搜索词 | `城市 + 长尾` | 10-15 |
| 竞品/关联词 | `竞品名`、`关联品牌` | 5-10 |

### 1.3 写入关键词文件

将种子关键词写入 `keywords.txt`，每行一个：

```
# 地域大词
苏州酒馆
苏州酒吧
苏州清吧

# 街道精准词
学士街
学士街酒馆

# 场景需求词
苏州夜生活
苏州约会
```

---

## Phase 2: 下拉框关联词采集

### 2.1 启动浏览器

确保浏览器已打开小红书页面并保持登录状态。

获取 profile ID：
```bash
opencli browser list
```

### 2.2 运行采集脚本

```bash
PROFILE=p9wmr42g \
  KEYWORDS_FILE=examples/keywords.txt \
  OUTPUT_DIR=./screenshots \
  WAIT_AFTER_TYPE=6 \
  bash scripts/batch_suggest.sh
```

### 2.3 人工提取关联词

逐张查看截图，将下拉框中的关联词记录到 `expanded_keywords.txt`。

**注意**：小红书搜索建议有缓存延迟，截图中的建议偶尔不是当前词的真实建议。但这些"错误"的建议本身也是真实存在的搜索词，同样可以纳入词库。

---

## Phase 3: 批量搜索笔记数据

### 3.1 执行搜索

对每个关键词（种子词 + 扩展词）执行：

```bash
mkdir -p data

for kw in $(cat keywords.txt expanded_keywords.txt | sort -u); do
  safe_name=$(echo "$kw" | sed 's/ /_/g')
  echo "搜索: $kw"
  opencli xiaohongshu search "$kw" --limit 50 -f json > "data/${safe_name}.json"
  sleep 3
done
```

### 3.2 数据字段说明

每个 JSON 文件包含该关键词搜索结果的前 50 篇笔记：
- `title` - 笔记标题
- `author` - 作者名
- `likes` - 点赞数
- `collects` - 收藏数
- `comments` - 评论数
- `date` - 发布日期
- `url` - 笔记链接

---

## Phase 4: 数据清洗与指标计算

### 4.1 Python 分析脚本

```python
import json, glob, os
from datetime import datetime

results = []

for filepath in glob.glob("data/*.json"):
    keyword = os.path.basename(filepath).replace(".json", "").replace("_", " ")
    with open(filepath) as f:
        data = json.load(f)

    notes = data.get("notes", [])
    if not notes:
        continue

    total = len(notes)
    avg_likes = sum(n["likes"] for n in notes) / total
    avg_collects = sum(n["collects"] for n in notes) / total
    avg_comments = sum(n["comments"] for n in notes) / total
    avg_engagement = avg_likes + avg_collects

    # 竞争度
    if total < 1000:
        competition = "低"
    elif total < 10000:
        competition = "中"
    else:
        competition = "高"

    # 互动度
    if avg_engagement > 5000:
        engagement = "高"
    elif avg_engagement > 1000:
        engagement = "中"
    else:
        engagement = "低"

    # 优质度
    if engagement == "高" and competition == "低":
        quality = "强烈推荐"
    elif engagement == "高" and competition == "中":
        quality = "推荐"
    elif engagement == "中" and competition == "低":
        quality = "推荐"
    elif engagement == "高" and competition == "高":
        quality = "可选"
    elif engagement == "中" and competition == "中":
        quality = "可选"
    else:
        quality = "备选"

    results.append({
        "keyword": keyword,
        "total_notes": total,
        "avg_likes": round(avg_likes, 1),
        "avg_collects": round(avg_collects, 1),
        "avg_comments": round(avg_comments, 1),
        "avg_engagement": round(avg_engagement, 1),
        "competition": competition,
        "engagement": engagement,
        "quality": quality,
        "date": datetime.now().strftime("%Y-%m-%d"),
    })

# 按优质度 + 互动度排序
results.sort(key=lambda x: (x["quality"], x["avg_engagement"]), reverse=True)

# 输出 CSV
import csv
with open("keywords_analysis.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=results[0].keys())
    writer.writeheader()
    writer.writerows(results)

print(f"分析完成，共 {len(results)} 个关键词")
print("结果已保存到 keywords_analysis.csv")
```

---

## Phase 5: 飞书表格导入

### 5.1 授权登录

```bash
lark-cli auth login --no-wait --json
```

按提示在浏览器完成 OAuth，脚本会自动轮询等待授权完成。

### 5.2 创建表格

在目标 base 中创建两张表：
- **关键词分析总表**（参考 README 中的字段定义）
- **笔记详情表**（参考 README 中的字段定义）

### 5.3 批量导入

```bash
lark-cli bitable record create \
  --app-token YOUR_APP_TOKEN \
  --table-id YOUR_TABLE_ID \
  --fields-file keywords_analysis.json
```

或使用飞书多维表格的 Web 界面上传 CSV。

---

## Phase 6: 数据分析与策略输出

### 6.1 筛选推荐关键词

在飞书中按以下条件过滤：
- 优质度 = "强烈推荐" 或 "推荐"
- 按 `avg_engagement` 降序排列

取 Top 10-15 作为核心布局关键词。

### 6.2 竞品内容分析

对每个推荐关键词，分析其 Top 10 笔记的：
- **标题结构**：数字型（"Top 5..."）、疑问型（"苏州哪里..."）、情绪型（"绝了！苏州..."）
- **常用标签**：高频出现的 #tag
- **内容形式**：图文、视频、短图文的比例
- **封面风格**：暖色调/冷色调、有人物/纯场景
- **发布时间**：集中在周几、什么时段

### 6.3 输出内容策略

基于以上分析，输出：
1. **标题模板库**（5-10个可直接套用的标题公式）
2. **标签组合推荐**（每组3-5个标签，覆盖核心词+长尾词）
3. **发布时间建议**（根据数据找出互动最高的时段）
4. **内容方向清单**（每个推荐关键词对应的内容切入点）

---

## 常见问题

### Q: 为什么截图中的下拉框显示的是上一个词的建议？
A: 小红书搜索建议有前端缓存机制。输入新词后，API 返回真实建议有 1-3 秒延迟。脚本已设置 5-8 秒等待，但在某些网络环境下仍可能捕获到缓存内容。这些"错误"建议本身也是真实搜索词，不影响词库质量。

### Q: 脚本执行时提示 "ref=2 not found in DOM"？
A: 检查是否执行了 `open` 命令刷新页面。页面刷新后所有 DOM 引用会失效。解决：保持当前页面不动，重新获取 state 查找新的 ref 编号。

### Q: 下拉框被笔记卡片挡住了？
A: 脚本已通过 JS 将卡片透明度设为 0.1 解决。如果仍有问题，可在浏览器开发者工具中手动执行：
```javascript
document.querySelectorAll("[class*=note]").forEach(c => c.style.opacity = "0.1")
```

### Q: 采集到的词太多，如何筛选？
A: 先全部保留。进入 Phase 3-4 后，用数据说话——笔记总数少的词优先布局（竞争度低），同时平均互动高的词说明用户需求真实存在。
