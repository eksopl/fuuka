var selected_style;
function replyhighlight(id){
	var tdtags=document.getElementsByTagName("td");
	var new_selected_style="reply";
	for(i=0; i<tdtags.length; i++){
		if(tdtags[i].className=="highlight"){
			tdtags[i].className=selected_style;
		}
		if(tdtags[i].id==id){
			new_selected_style=tdtags[i].className;
			tdtags[i].className="highlight";
		}
	}
	selected_style=new_selected_style;
}

function insert(text){
	var textarea=document.forms.postform.KOMENTO;
	if(!textarea) return;
	
	if(textarea.createTextRange && textarea.caretPos){
		var caretPos=textarea.caretPos;
		caretPos.text=caretPos.text.charAt(caretPos.text.length-1)==" "?text+" ":text;
	} else if(textarea.setSelectionRange){
		var start=textarea.selectionStart;
		var end=textarea.selectionEnd;
		textarea.value=textarea.value.substr(0,start)+text+textarea.value.substr(end);
		textarea.setSelectionRange(start+text.length,start+text.length);
	} else{
		textarea.value+=text+" ";
	}
	textarea.focus();
}

function get_cookie(name){
	with(document.cookie){
		var regexp=new RegExp("(^|;\\s+)"+name+"=(.*?)(;|$)");
		var hit=regexp.exec(document.cookie);
		if(hit&&hit.length>2) return decodeURIComponent(hit[2]);
		else return '';
	}
};

function toggle(id){
	var elem;
	
	if(!(elem=document.getElementById(id))) return;

	elem.style.display=elem.style.display?"":"none";
}

function who_are_you_quoting(e) {
	var parent, d, clr, src, cnt, left, top, width, maxWidth;
	
	maxWidth = 500;
	
	e = e.target || window.event.srcElement;
	
	cnt = document.createElement('div');
	cnt.id = 'q-p';
	
	src = document.getElementById(e.getAttribute('href').split('#')[1]);
	
	width = src.offsetWidth;
	if (width > maxWidth) {
		width = maxWidth;
	}
	src = src.cloneNode(true);
	src.id = 'q-p-s';
	if (src.tagName == 'DIV') {
		src.setAttribute('class', 'q-p-op');
		clr = document.createElement('div');
		clr.setAttribute('class', 'newthr');
		src.appendChild(clr);
	}
	
	left = 0;
	top = e.offsetHeight + 1;
	parent = e;
	do {
		left += parent.offsetLeft;
		top += parent.offsetTop;
	} while (parent = parent.offsetParent);
	
	if ((d = document.body.offsetWidth - left - width) < 0) {
		left += d;
	}
	
	cnt.setAttribute('style', 'left:' + left + 'px;top:' + top + 'px;');
	cnt.appendChild(src);
	document.body.appendChild(cnt);
}

function remove_quote_preview(e) {
	var cnt;
	if (cnt = document.getElementById('q-p')) {
		document.body.removeChild(cnt);
	}
}

function quotePreview() {
	var quotes = document.forms.postform.getElementsByClassName('backlink');
	for (i = 0, j = quotes.length; i < j; ++i) {
		quotes[i].addEventListener('mouseover', who_are_you_quoting, false);
		quotes[i].addEventListener('mouseout', remove_quote_preview, false);
	}
}

function backlink() {
	var i, j, ii, jj, tid, bl, qb, t, form, backlinks, linklist, replies;
	
	form = document.forms.postform;
	
	if (!(replies = form.getElementsByClassName('reply'))) {
		return;
	}
	
	for (i = 0, j = replies.length; i < j; ++i) {
		if (!(backlinks = replies[i].getElementsByClassName('backlink'))) {
			continue;
		}
		linklist = {};
		for (ii = 0, jj = backlinks.length; ii < jj; ++ii) {
			tid = backlinks[ii].getAttribute('href').split(/#/);
			if (!(t = document.getElementById(tid[1]))) {
				continue;
			}
			if (t.tagName == 'DIV') {
				backlinks[ii].textContent = '>>OP';
			}
			bl = document.createElement('a');
			bl.className = 'backlink';
			bl.href = '#' + replies[i].id;
			bl.textContent = '>>' + replies[i].id.slice(1);
			if (!(qb = t.getElementsByClassName('quoted-by')[0])) {
				qb = document.createElement('div');
				qb.className = 'quoted-by';
				qb.textContent = 'Quoted by: ';
				linklist[replies[i].id] = true;
				qb.appendChild(bl);
				t.insertBefore(qb, t.getElementsByTagName('blockquote')[0]);
			}
			else {
				if (linklist[replies[i].id]) {
					continue;
				}
				linklist[replies[i].id] = true;
				qb.appendChild(document.createTextNode(' '));
				qb.appendChild(bl);
			}
		}
	}
}

function run() {
	var i, j, quotes, arr = location.href.split(/#/);
	
	if(arr[1]) 
		replyhighlight(arr[1]);
	
	if(document.forms.postform && document.forms.postform.NAMAE)
		document.forms.postform.NAMAE.value=get_cookie("name");
	
	if(document.forms.postform && document.forms.postform.MERU)
		document.forms.postform.MERU.value=get_cookie("email");

	if(document.forms.postform && document.forms.postform.delpass)
		document.forms.postform.delpass.value=get_cookie("delpass");
	
	if (document.getElementsByClassName) {
		backlink();
		quotePreview();
	}
}

if (window.addEventListener) {
	window.addEventListener('DOMContentLoaded', run, false);
}
else {
	window.onload = run;
}
