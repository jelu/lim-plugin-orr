(function ($) {
	$(function () {
		window.lim.plugin.orr = {
			init: function () {
				var that = this;
				
				$('.sidebar-nav a[href="#about"]').click(function () {
					$('.sidebar-nav li').removeClass('active');
					$(this).parent().addClass('active');
					that.loadAbout();
					return false;
				});
				
				this.loadAbout();
			},
			//
			loadAbout: function () {
				window.lim.loadPage('/_orr/about.html')
				.done(function (data) {
					window.lim.display(data, '#orr-content');
				});
			},
		};
		window.lim.plugin.orr.init();
	});
})(window.jQuery);
