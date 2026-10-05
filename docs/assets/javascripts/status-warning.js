document.addEventListener("DOMContentLoaded", () => {


    const meta = document.querySelector(
        'meta[name="status"]'
    );

    if (!meta) return;

    const status = meta.content.trim().toLowerCase();

    if (!status || ["active", "actiu", "approved"].includes(status)) {
        return;
    }

    const article =
        document.querySelector(".md-content__inner");

    if (!article) {
        return;
    }

    const warning = document.createElement("div");

    warning.className = "admonition warning";

    const messages = new Map([
        ["draft", [
            "Document en construcció",
            "Aquest document està en construcció i pot contenir informació incompleta o incorrecta."
        ]],
        ["review", [
            "Document pendent d'aprovació",
            "Aquest document està en revisió i encara no s'ha aprovat."
        ]],
        ["deprecated", [
            "Document obsolet",
            "Aquest document està obsolet i pot contenir informació que ja no és vàlida."
        ]]
    ]);
    const [title, message] = messages.get(status) || [
        "Document no actiu",
        `Aquest document té l'estat «${status}» i pot contenir informació incompleta o desactualitzada.`
    ];
    const titleElement = document.createElement("p");
    titleElement.className = "admonition-title";
    titleElement.textContent = title;
    const messageElement = document.createElement("p");
    messageElement.textContent = message;
    warning.append(titleElement, messageElement);

    article.prepend(warning);
});
