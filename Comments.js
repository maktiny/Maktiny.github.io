import React, {Component} from "react";

export default class Comments extends Component {
  constructor(props){ 
    super(props);
    this.commentBox = React.createRef(); 
  }
  componentDidMount () {
      let scriptEl = document.createElement("script");
      scriptEl.setAttribute("src", "https://utteranc.es/client.js");
      scriptEl.setAttribute("crossorigin","anonymous");
      scriptEl.setAttribute("async", true);
      scriptEl.setAttribute("repo", "maktiny/Maktiny.github.io");
      scriptEl.setAttribute("issue-term", "pathname");
      scriptEl.setAttribute( "theme", "github-light");
      this.commentBox.current.appendChild(scriptEl);
  }

  render() {
    return (
        <div>
          <div ref={this.commentBox} className="comment-box"/>
          {/* Above element is where the comments are injected */}
        </div>
    );
  }
}
