import streamlit as st
import pandas as pd
import psycopg2
st.title("AI query dashboard")

conn = psycopg2.connect(
    host="localhost", dbname="postgres", user="rohanpandey")
df = pd.read_sql("SELECT * FROM llm_logs", conn)

c1, c2, c3 = st.columns(3)
c1.metric("Total cost", f"${df['cost_usd'].sum():.4f}")
c2.metric("Input tokens", f"{df['input_tokens'].sum():,}")
c3.metric("Output tokens", f"{df['output_tokens'].sum():,}")

st.subheader("Spend by feature")
feature = df.groupby("feature")["cost_usd"].sum()
st.bar_chart(feature)

st.subheader("Token usage over time")
df["date"] = pd.to_datetime(df["created_at"]).dt.date
df["total_tokens"] = df["input_tokens"] + df["output_tokens"]
spending_over_time = df.groupby("date")["total_tokens"].sum()
st.line_chart(spending_over_time)

st.subheader("spending_per_model")
df["model_short"] = df["model"].str.split("/").str[-1]
by_model = df.groupby("model_short")["cost_usd"].sum()
st.bar_chart(by_model)
