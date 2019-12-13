function centerCanvas() {
  var x = (windowWidth - width) / 2;
  var y = (windowHeight - height) / 2;
  cnv.position(x, y);
}

function setup() {
  cnv = createCanvas(800, 400);
  centerCanvas();
  background(32, 32, 32);
}

function windowResized() {
  centerCanvas();
}

function randomColor() {
  var a = random(0, 255);
  var b = random(0, 255);
  var c = random(0, 255);
  background(a, b, c);
}

function draw() {
  var d = random(0, 255);
  var e = random(0, 255);
  var f = random(0, 255);
  fill(d,e,f);
  noStroke();
  ellipse(mouseX, mouseY, 25, 25);
}