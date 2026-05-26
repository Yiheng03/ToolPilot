import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const v1Dir = path.resolve(__dirname, "..")
const benchmarkPath = path.join(v1Dir, "tool_quote_benchmark_v1.json")
const generatedDatasetPath = path.join(v1Dir, "benchmark", "generated", "tool_quote_agent_eval_v1.json")
const resultsDir = path.join(v1Dir, "results")
const resultDatasetPath = path.join(resultsDir, "4th_0525_agent_eval_dataset.json")
const summaryPath = path.join(resultsDir, "4th_0525_agent_eval_stub_summary.md")

function text(value) {
  if (value == null) return ""
  if (Array.isArray(value)) return value.filter((item) => item != null).join(" / ")
  if (typeof value === "object") return JSON.stringify(value)
  return String(value)
}

function loadQuestionsOnly() {
  const parsed = JSON.parse(fs.readFileSync(benchmarkPath, "utf8"))
  const questions = Array.isArray(parsed) ? parsed : parsed.questions
  if (!Array.isArray(questions)) throw new Error("Benchmark file does not contain questions")
  return questions.map((item, index) => ({
    id: item.id ?? `q_${String(index + 1).padStart(3, "0")}`,
    input: {
      question: text(item.question),
    },
  }))
}

function loadExpectedDataset() {
  if (!fs.existsSync(generatedDatasetPath)) return null
  const dataset = JSON.parse(fs.readFileSync(generatedDatasetPath, "utf8"))
  if (!Array.isArray(dataset)) throw new Error("Generated agent eval dataset is not an array")
  return dataset
}

function buildSummary({ runAt, inputOnlyCount, expectedDatasetCount }) {
  return [
    "# Agent Eval Stub - 4th_0525",
    "",
    `- run_at: ${runAt}`,
    '- agent_eval_status: "stub_only"',
    `- input_only_questions: ${inputOnlyCount}`,
    `- generated_agent_eval_dataset: ${expectedDatasetCount}`,
    "",
    "agent_eval 数据集已经生成。",
    "",
    "当前未接入智能体问答接口，runner 只构造 question-only 输入列表，不会把 answer_supplier / answer_category / answer_spec / answer_price 传给被测智能体。",
    "",
    "暂未产生端到端智能体分数。",
    "",
  ].join("\n")
}

function main() {
  fs.mkdirSync(resultsDir, { recursive: true })
  const runAt = new Date().toISOString()
  const questionOnlyInputs = loadQuestionsOnly()
  const expectedDataset = loadExpectedDataset() ?? questionOnlyInputs.map((item) => ({
    ...item,
    expected: {
      supplier: null,
      category: null,
      spec: null,
      price: null,
      priceLabel: null,
    },
    scoring: {
      supplier: 0.25,
      category: 0.25,
      spec: 0.25,
      price: 0.25,
    },
  }))

  fs.writeFileSync(resultDatasetPath, JSON.stringify(expectedDataset, null, 2), "utf8")
  fs.writeFileSync(summaryPath, buildSummary({ runAt, inputOnlyCount: questionOnlyInputs.length, expectedDatasetCount: expectedDataset.length }), "utf8")

  console.log('agent_eval_status = "stub_only"')
  console.log(`question_only_inputs: ${questionOnlyInputs.length}`)
  console.log(`agent_eval dataset samples: ${expectedDataset.length}`)
  console.log(`summary: ${summaryPath}`)
  console.log(`agent eval dataset: ${resultDatasetPath}`)
}

main()
