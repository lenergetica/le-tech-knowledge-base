document.addEventListener("DOMContentLoaded", () => {

    const meta = document.querySelector(
        'meta[name="review_date"]'
    );

    if (!meta) return;

    const reviewDate = new Date(meta.content);

    const sixMonthsAgo = new Date();
    sixMonthsAgo.setMonth(
        sixMonthsAgo.getMonth() - 6
    );

    if (reviewDate >= sixMonthsAgo) {
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
            durant els darrers 6 mesos.
        </p>
    `;

    article.prepend(warning);
});
