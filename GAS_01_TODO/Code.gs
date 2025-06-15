// 시트 설정
const SHEET_NAME = 'TodoList';
const API_KEY = 'AIzaSyA3Dg__rgtQ4j3GRrb4wM10bbU0M6sLGww';
const SPREADSHEET_ID = '1grWlkZb6ed7WzU9xdVlTDApL5MxJ1ZMqYKDG_lR5Ukw';

function doGet() {
  const template = HtmlService.createTemplateFromFile('index');
  const htmlOutput = template.evaluate()
    .setTitle('TODO Cloud')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL)
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setContent(`
      <meta http-equiv="Content-Security-Policy" content="
        default-src 'self';
        script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdnjs.cloudflare.com https://d3js.org;
        style-src 'self' 'unsafe-inline';
        img-src 'self' data:;
        connect-src 'self';
      ">
      <script>
        // iframe sandbox 보안 설정
        window.addEventListener('load', function() {
          const iframes = document.getElementsByTagName('iframe');
          for (let iframe of iframes) {
            iframe.setAttribute('sandbox', 'allow-scripts');
          }
        });
      </script>
    ` + template.evaluate().getContent());
  
  return htmlOutput;
}

function include(filename) {
  return HtmlService.createHtmlOutputFromFile(filename).getContent();
}

// 할일 목록 조회
function getTodos() {
  try {
    console.log('시트 접근 시작');
    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    console.log('스프레드시트 접근 성공');
    
    let sheet = ss.getSheetByName(SHEET_NAME);
    console.log('시트 존재 여부:', !!sheet);
    
    if (!sheet) {
      console.log('시트가 없습니다. 새로 생성합니다.');
      sheet = ss.insertSheet(SHEET_NAME);
      sheet.appendRow(['ID', '할일', '상태', '생성일']);
      return [];
    }
    
    const data = sheet.getDataRange().getValues();
    console.log('데이터 행 수:', data.length);
    
    if (data.length <= 1) {
      console.log('헤더만 있거나 데이터가 없습니다.');
      return [];
    }
    
    const headers = data.shift();
    console.log('헤더:', headers);
    
    const todos = data.map(row => ({
      id: row[0],
      todo: row[1],
      status: row[2],
      created: row[3]
    }));
    
    console.log('변환된 할일 목록:', todos);
    return todos;
    
  } catch (error) {
    console.error('시트 접근 오류:', error.toString());
    console.error('오류 상세:', error);
    return [];
  }
}

// 할일 추가
function addTodo(todo) {
  try {
    console.log('할일 추가 시작:', todo);
    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let sheet = ss.getSheetByName(SHEET_NAME);
    
    if (!sheet) {
      sheet = ss.insertSheet(SHEET_NAME);
      sheet.appendRow(['ID', '할일', '상태', '생성일']);
    }
    
    const id = Utilities.getUuid();
    sheet.appendRow([id, todo, '진행중', new Date()]);
    console.log('할일 추가 완료, ID:', id);
    return id;
  } catch (error) {
    console.error('할일 추가 오류:', error);
    throw error;
  }
}

// 할일 상태 업데이트
function updateTodoStatus(id, status) {
  try {
    console.log('상태 업데이트 시작:', id, status);
    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = ss.getSheetByName(SHEET_NAME);
    const data = sheet.getDataRange().getValues();
    
    for (let i = 1; i < data.length; i++) {
      if (data[i][0] === id) {
        sheet.getRange(i + 1, 3).setValue(status);
        console.log('상태 업데이트 완료');
        break;
      }
    }
  } catch (error) {
    console.error('상태 업데이트 오류:', error);
    throw error;
  }
}

// 할일 삭제
function deleteTodo(id) {
  try {
    console.log('할일 삭제 시작:', id);
    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = ss.getSheetByName(SHEET_NAME);
    const data = sheet.getDataRange().getValues();
    
    for (let i = 1; i < data.length; i++) {
      if (data[i][0] === id) {
        sheet.deleteRow(i + 1);
        console.log('할일 삭제 완료');
        break;
      }
    }
  } catch (error) {
    console.error('할일 삭제 오류:', error);
    throw error;
  }
}

// Gemini API를 통한 조언과 성경 구절 가져오기
function getAdviceAndVerses(todo) {
  try {
    console.log('조언 요청 시작:', todo);
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.0-flash:generateContent?key=${API_KEY}`;
    
    const prompt = `다음 할일에 대한 조언과 관련된 성경 구절을 추천해주세요:
    할일: ${todo}
    
    다음 형식으로 응답해주세요:
    1. 조언: (할일 수행을 위한 구체적인 조언)
    2. 성경 구절:
       - 구약: (개혁한글) / (NIV)
       - 신약: (개혁한글) / (NIV)
       - 시편: (개혁한글) / (NIV)
       - 잠언: (개혁한글) / (NIV)`;
    
    const options = {
      method: 'post',
      contentType: 'application/json',
      payload: JSON.stringify({
        contents: [{
          parts: [{
            text: prompt
          }]
        }]
      })
    };
    
    const response = UrlFetchApp.fetch(url, options);
    const result = JSON.parse(response.getContentText());
    console.log('조언 요청 완료');
    return result.candidates[0].content.parts[0].text;
  } catch (error) {
    console.error('조언 요청 오류:', error);
    return '죄송합니다. 조언을 가져오는데 실패했습니다.';
  }
}
