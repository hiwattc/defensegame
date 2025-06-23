// 스프레드시트 ID를 설정합니다
const SPREADSHEET_ID = '1grWlkZb6ed7WzU9xdVlTDApL5MxJ1ZMqYKDG_lR5Ukw';
const SHEET_NAME = '할일목록';

// 웹앱을 실행할 때 호출되는 함수
function doGet() {
  return HtmlService.createTemplateFromFile('index')
    .evaluate()
    .setTitle('할일 관리')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

// HTML 파일에 포함할 JavaScript와 CSS 파일을 로드하는 함수
function include(filename) {
  return HtmlService.createHtmlOutputFromFile(filename).getContent();
}

// 할일 목록을 가져오는 함수
function getTodos() {
  const sheet = SpreadsheetApp.openById(SPREADSHEET_ID).getSheetByName(SHEET_NAME);
  const data = sheet.getDataRange().getValues();
  const headers = data[0];
  const todos = [];
  
  for (let i = 1; i < data.length; i++) {
    todos.push({
      id: i,
      title: data[i][0],
      description: data[i][1],
      dueDate: data[i][2],
      status: data[i][3]
    });
  }
  
  return todos;
}

// 새로운 할일을 추가하는 함수
function addTodo(todo) {
  const sheet = SpreadsheetApp.openById(SPREADSHEET_ID).getSheetByName(SHEET_NAME);
  sheet.appendRow([todo.title, todo.description, todo.dueDate, todo.status]);
  return getTodos();
}

// 할일을 수정하는 함수
function updateTodo(todo) {
  const sheet = SpreadsheetApp.openById(SPREADSHEET_ID).getSheetByName(SHEET_NAME);
  const row = todo.id + 1;
  sheet.getRange(row, 1, 1, 4).setValues([[todo.title, todo.description, todo.dueDate, todo.status]]);
  return getTodos();
}

// 할일을 삭제하는 함수
function deleteTodo(id) {
  const sheet = SpreadsheetApp.openById(SPREADSHEET_ID).getSheetByName(SHEET_NAME);
  sheet.deleteRow(id + 1);
  return getTodos();
}
