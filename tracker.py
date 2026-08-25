from functools import lru_cache
import requests
import psycopg2
import logging


@lru_cache(maxsize=1)
def get_price_openrouter():
    res = requests.get("https://openrouter.ai/api/v1/models", timeout=10)
    res.raise_for_status()
    return {
        m["id"]: (float(m["pricing"]["prompt"]),
                  float(m["pricing"]["completion"]))
        for m in res.json()["data"]
    }


FALLBACK_PRICES = {
    # OpenAI direct — used by labgrader/nbgrader/apis/openaiapi.py
    "gpt-4o-2024-08-06":  {"input": 2.50 / 1e6,  "output": 10.00 / 1e6},
    "gpt-4-turbo":        {"input": 10.00 / 1e6, "output": 30.00 / 1e6},
    "gpt-3.5-turbo-0125": {"input": 0.50 / 1e6,  "output": 1.50 / 1e6},
    "o3-2025-04-16":      {"input": 2.00 / 1e6,  "output": 8.00 / 1e6},
}


def price_func(model, provider):
    if provider == "openrouter":
        prices = get_price_openrouter().get(model)
        if prices:
            return prices
    p = FALLBACK_PRICES.get(model)
    return (p["input"], p["output"]) if p else None


def log_to_db(provider, model, input_tokens, output_tokens, feature, call_type, pages=None):
    try:
        prices = price_func(model, provider)
        if prices is None:
            cost = None
        else:
            in_rate, out_rate = prices
            cost = in_rate * input_tokens + out_rate * output_tokens

        conn = psycopg2.connect(
            host="localhost",
            dbname="postgres",
            user="rohanpandey",
        )
        try:
            cur = conn.cursor()
            cur.execute("INSERT INTO llm_logs (provider, model, input_tokens, output_tokens, cost_usd,feature, call_type,pages) VALUES(%s,%s,%s,%s,%s,%s,%s,%s)",
                        (provider, model, input_tokens, output_tokens, cost, feature, call_type, pages))
            conn.commit()
        finally:
            conn.close()
    except Exception as e:
        logging.warning(f"llm_tracker: failed to log usage: {e}")


if __name__ == "__main__":
    log_to_db("openrouter", "openai/gpt-4o", 1200, 400, "agent_chat", "chat")
    log_to_db("openrouter", "anthropic/claude-sonnet-4",
              800, 350, "agent_chat", "chat")
    log_to_db("openrouter", "openai/gpt-4o", 2000, 900, "agent_chat", "chat")
    log_to_db("openrouter", "google/gemini-3-flash-preview",
              600, 250, "question_bank", "chat")
    log_to_db("openrouter", "anthropic/claude-sonnet-4",
              1500, 700, "question_bank", "chat")
    log_to_db("openai", "gpt-4-turbo", 500, 200, "generate_assignment", "chat")
    log_to_db("openai", "gpt-4o-2024-08-06", 900, 300, "modify_cell", "chat")
    log_to_db("openrouter", "openai/text-embedding-3-small",
              400, 0, "topic_ontology", "embedding")
    log_to_db("openrouter", "google/gemini-3-pro-image-preview",
              120, 0, "image_gen", "image")
    log_to_db("mistral", "mistral-ocr-latest", 0, 0, "ocr", "ocr", pages=8)
    print("done")
