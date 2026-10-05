document.addEventListener("DOMContentLoaded", () => {

    const meta = document.querySelector(
        'meta[name="review_date"]'
    );

    if (!meta) return;

    const reviewDate = new Date(meta.content);

    if (Number.isNaN(reviewDate.getTime())) return;

    const periodMeta = document.querySelector(
        'meta[name="review_period_months"]'
    );
    const configuredMonths = Number(periodMeta?.content);
    const reviewPeriodMonths = Number.isInteger(configuredMonths) && configuredMonths > 0
        ? configuredMonths
        : 6;

    const reviewCutoff = new Date();
    reviewCutoff.setMonth(
        reviewCutoff.getMonth() - reviewPeriodMonths
    );

    if (reviewDate >= reviewCutoff) {
        return;
    }

    const article =
        document.querySelector(".md-content__inner");

    if (!article) {
        return;
    }

    const warning = document.createElement("div");

    warning.className = "admonition warning";

    warning.innerHTML = `
        <p class="admonition-title">
            Document pendent de revisió
        </p>
        <p>
            Aquest document no s'ha revisat
            durant ${reviewPeriodMonths === 1 ? "el darrer mes" : `els darrers ${reviewPeriodMonths} mesos`}.
        </p>
    `;

    article.prepend(warning);
});
