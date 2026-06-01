import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./styles.css";

class ErrorBoundary extends React.Component {
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
        <div className="fatalShell">
          <div className="fatalCard">
            <h1>화면 오류</h1>
            <p>아래 오류 문구를 보내줘.</p>
            <pre>{String(this.state.error?.message || this.state.error)}</pre>
            <button onClick={() => location.reload()}>새로고침</button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>
);
