document.addEventListener("DOMContentLoaded", () => {
    const statusMeta = document.querySelector('meta[name="status"]');

    if (!statusMeta) {
        return;
    }

    const status = statusMeta.content.trim().toLowerCase();

    if (!status) {
        return;
    }

    const activeStatuses = ["active", "actiu", "approved"];
    let title;
    let message;

    if (activeStatuses.includes(status)) {
        const reviewDateMeta = document.querySelector('meta[name="review_date"]');

        if (!reviewDateMeta) {
            return;
        }

        const reviewDate = new Date(reviewDateMeta.content);

        if (Number.isNaN(reviewDate.getTime())) {
            return;
        }

        const periodMeta = document.querySelector('meta[name="review_period_months"]');
        const configuredMonths = Number(periodMeta?.content);
        const reviewPeriodMonths = Number.isInteger(configuredMonths) && configuredMonths > 0
            ? configuredMonths
            : 6;
        const reviewCutoff = new Date();
        reviewCutoff.setMonth(reviewCutoff.getMonth() - reviewPeriodMonths);

        if (reviewDate >= reviewCutoff) {
            return;
        }

        title = "Document pendent de revisió";
        message = `Aquest document no s'ha revisat durant ${
            reviewPeriodMonths === 1
                ? "el darrer mes"
                : `els darrers ${reviewPeriodMonths} mesos`
        }.`;
    } else {
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
        [title, message] = messages.get(status) || [
            "Document no actiu",
            `Aquest document té l'estat «${status}» i pot contenir informació incompleta o desactualitzada.`
        ];
    }

    const article = document.querySelector(".md-content__inner");

    if (!article) {
        return;
    }

    const warning = document.createElement("div");
    warning.className = "admonition warning";

    const titleElement = document.createElement("p");
    titleElement.className = "admonition-title";
    titleElement.textContent = title;

    const messageElement = document.createElement("p");
    messageElement.textContent = message;

    warning.append(titleElement, messageElement);
    article.prepend(warning);
});
