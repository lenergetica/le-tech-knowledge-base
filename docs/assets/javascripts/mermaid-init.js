document$.subscribe(() => {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "loose",
    theme: "default",
    flowchart: {
      curve: "basis"
    }
  });
  mermaid.run({
    querySelector: ".mermaid"
  });
});
