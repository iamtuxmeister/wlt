// wlt — client JS
// Add Alpine.js, HTMX, or whatever you prefer here.
document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".flash").forEach(el => {
        setTimeout(() => el.remove(), 5000);
    });
});
