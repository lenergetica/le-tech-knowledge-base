document$.subscribe(() => {
  mermaid.initialize({
    startOnLoad: true,
    securityLevel: "loose",
    theme: "default",
    flowchart: {
      curve: "basis"
    }
  });
});
