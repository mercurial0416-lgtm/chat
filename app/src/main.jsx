import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./styles.css";

class AppErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error("App crashed", error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div
          style={{
            minHeight: "100dvh",
            display: "grid",
            placeItems: "center",
            padding: 20,
            background: "#f4f5f7",
            color: "#17181c",
            fontFamily:
              "system-ui, -apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', sans-serif",
          }}
        >
          <div
            style={{
              width: "min(420px, 100%)",
              background: "#fff",
              border: "1px solid rgba(20,24,32,.1)",
              borderRadius: 20,
              padding: 20,
              boxShadow: "0 12px 30px rgba(15,23,42,.08)",
            }}
          >
            <h1 style={{ margin: "0 0 8px", fontSize: 22 }}>
              화면 오류가 발생했어
            </h1>
            <p
              style={{
                margin: "0 0 14px",
                color: "#69707d",
                lineHeight: 1.45,
              }}
            >
              임시 오류 화면이야. 새로고침 후에도 반복되면 콘솔 오류를 보내줘.
            </p>
            <pre
              style={{
                whiteSpace: "pre-wrap",
                overflow: "auto",
                maxHeight: 160,
                background: "#f1f3f5",
                padding: 12,
                borderRadius: 12,
                fontSize: 12,
              }}
            >
              {String(this.state.error?.message || this.state.error)}
            </pre>
            <button
              onClick={() => location.reload()}
              style={{
                marginTop: 14,
                width: "100%",
                height: 44,
                border: 0,
                borderRadius: 14,
                background: "#fee500",
                color: "#191919",
                fontWeight: 800,
              }}
            >
              새로고침
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <AppErrorBoundary>
      <App />
    </AppErrorBoundary>
  </React.StrictMode>
);
