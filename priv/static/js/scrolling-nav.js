var _____WB$wombat$assign$function_____=function(name){return (self._wb_wombat && self._wb_wombat.local_init && self._wb_wombat.local_init(name))||self[name];};if(!self.__WB_pmw){self.__WB_pmw=function(obj){this.__WB_source=obj;return this;}}{
let window = _____WB$wombat$assign$function_____("window");
let self = _____WB$wombat$assign$function_____("self");
let document = _____WB$wombat$assign$function_____("document");
let location = _____WB$wombat$assign$function_____("location");
let top = _____WB$wombat$assign$function_____("top");
let parent = _____WB$wombat$assign$function_____("parent");
let frames = _____WB$wombat$assign$function_____("frames");
let opens = _____WB$wombat$assign$function_____("opens");
//jQuery to collapse the navbar on scroll
$(window).scroll(function() {
    if ($(".navbar").offset().top > 50) {
        $(".navbar-fixed-top").addClass("top-nav-collapse");
    } else {
        $(".navbar-fixed-top").removeClass("top-nav-collapse");
    }
});

//jQuery for page scrolling feature - requires jQuery Easing plugin
$(function() {
    $('a.page-scroll').bind('click', function(event) {
        var $anchor = $(this);
        $('html, body').stop().animate({
            scrollTop: $($anchor.attr('href')).offset().top
        }, 1500, 'easeInOutExpo');
        event.preventDefault();
    });
});


// Keep the viewport pinned to the top of the teachings section whenever its
// content is swapped via htmx. Swapping in content of a different height
// (book list vs. book teachings vs. a single teaching) changes the document
// height while the browser's scrollY stays fixed, which visually reads as
// the page jumping away from where the user was.
document.body.addEventListener('htmx:afterSettle', function (evt) {
    if (evt.detail.target && evt.detail.target.id === 'teachings-panel') {
        var $teachings = $('#teachings');
        if ($teachings.length) {
            $('html, body').stop().scrollTop($teachings.offset().top);
        }
    }
});

// tab nav-pill on #tab_ navigation

var hash = document.location.hash;
var prefix = "tab_";
if (hash) {
    $('.nav-pills a[href="'+hash.replace(prefix,"")+'"]').tab('show');
} 

// Change hash for page-reload
$('.nav-pills a').on('shown', function (e) {
    window.location.hash = e.target.hash.replace("#", "#" + prefix);
});


}

/*
     FILE ARCHIVED ON 18:39:34 May 21, 2017 AND RETRIEVED FROM THE
     INTERNET ARCHIVE ON 14:16:04 Apr 07, 2026.
     JAVASCRIPT APPENDED BY WAYBACK MACHINE, COPYRIGHT INTERNET ARCHIVE.

     ALL OTHER CONTENT MAY ALSO BE PROTECTED BY COPYRIGHT (17 U.S.C.
     SECTION 108(a)(3)).
*/
/*
playback timings (ms):
  captures_list: 0.582
  exclusion.robots: 0.051
  exclusion.robots.policy: 0.04
  esindex: 0.011
  cdx.remote: 91.368
  LoadShardBlock: 379.811 (3)
  PetaboxLoader3.datanode: 143.26 (4)
  load_resource: 172.9
*/