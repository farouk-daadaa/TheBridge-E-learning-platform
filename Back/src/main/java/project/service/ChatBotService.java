package project.service;

import org.json.JSONArray;
import org.json.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class ChatBotService {

    private static final Logger logger = LoggerFactory.getLogger(ChatBotService.class);

    @Value("${openrouter.api.key}")
    private String API_KEY;

    @Value("${chatbot.cache.timeout}")
    private long cacheTimeoutSeconds;

    // OpenRouter chat completions endpoint (fixed)
    private static final String API_URL = "https://openrouter.ai/api/v1/chat/completions";

    // Change this to the OpenRouter model you want to use
    private static final String MODEL_NAME = "deepseek/deepseek-r1-0528-qwen3-8b:free";

    // Cache: question -> {answer, timestamp}
    private final Map<String, CacheEntry> answerCache = new ConcurrentHashMap<>();

    private static class CacheEntry {
        String answer;
        long timestamp;

        CacheEntry(String answer, long timestamp) {
            this.answer = answer;
            this.timestamp = timestamp;
        }
    }

    public String ask(String question) {
        try {
            String cacheKey = question.trim().toLowerCase();

            // Check cache first
            CacheEntry cached = answerCache.get(cacheKey);
            if (cached != null) {
                long now = System.currentTimeMillis() / 1000;
                if (now - cached.timestamp < cacheTimeoutSeconds) {
                    logger.debug("Returning cached answer for question: {}", question);
                    return cached.answer;
                } else {
                    logger.debug("Cache expired for question: {}", question);
                    answerCache.remove(cacheKey);
                }
            }

            // Build prompt (your existing prompt)
            String prompt = """
You are 9antraBot, a helpful AI tutor on the 9antra e-learning platform. Your role is to assist students by answering their questions about the platform or their learning in a clear, accurate, and beginner-friendly way.

**About 9antra**:
- Students can enroll in online courses, follow instructors, bookmark courses, leave reviews, track progress, and join live sessions.
- Instructors create courses and live sessions; some sessions are restricted to followers only (using 100ms video).
- Features include profile management, two-factor authentication, and course progress tracking.

**Instructions**:
- Answer **only** the question asked, providing a direct, complete, and focused response.
- Do not include additional questions, promotional content (e.g., "Join 9antra"), speculative follow-ups, or references to 9antra unless the question is about the platform.
- For platform questions (e.g., "How do I follow an instructor?" or "How do I join a session?"), describe the steps clearly, referencing 9antra’s features.
- For learning questions (e.g., "What is a class in Java?"), provide a clear explanation with examples if relevant.
- If the question is unclear or unrelated, politely ask for clarification or give a brief educational response.
- Keep answers concise, informative, and free of jargon.
- Stop immediately after answering the question.

Question: """ + question + """

Answer:
""";

            // Build JSON body for OpenRouter request
            JSONObject body = new JSONObject();
            body.put("model", MODEL_NAME);

            JSONArray messages = new JSONArray();

            // System message (the prompt sets context)
            JSONObject systemMessage = new JSONObject();
            systemMessage.put("role", "system");
            systemMessage.put("content", prompt);
            messages.put(systemMessage);

            // User message (the question itself)
            JSONObject userMessage = new JSONObject();
            userMessage.put("role", "user");
            userMessage.put("content", question);
            messages.put(userMessage);

            body.put("messages", messages);

            // Optional: temperature, max tokens, top_p etc.
            JSONObject parameters = new JSONObject();
            parameters.put("temperature", 0.7);
            parameters.put("max_tokens", 600);
            parameters.put("top_p", 0.9);
            body.put("parameters", parameters);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(API_URL))
                    .header("Authorization", "Bearer " + API_KEY)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body.toString()))
                    .build();

            // Retry logic
            for (int attempt = 1; attempt <= 3; attempt++) {
                try {
                    logger.debug("Sending request to OpenRouter API, attempt {}", attempt);
                    HttpResponse<String> response = HttpClient.newHttpClient()
                            .send(request, HttpResponse.BodyHandlers.ofString());

                    String responseBody = response.body();
                    logger.debug("Received response: {}", responseBody);

                    if (response.statusCode() != 200) {
                        logger.error("Non-200 response: {} - {}", response.statusCode(), responseBody);
                        if (attempt == 3) {
                            return "API error (status " + response.statusCode() + "): " + responseBody;
                        }
                        Thread.sleep(2000L * attempt);
                        continue;
                    }

                    JSONObject jsonResponse = new JSONObject(responseBody);

                    if (!jsonResponse.has("choices")) {
                        logger.error("No choices field in response");
                        return "Unexpected API response format.";
                    }

                    JSONArray choices = jsonResponse.getJSONArray("choices");
                    if (choices.isEmpty()) {
                        logger.warn("Empty choices array");
                        return "The model didn't return a response.";
                    }

                    JSONObject firstChoice = choices.getJSONObject(0);
                    JSONObject message = firstChoice.getJSONObject("message");
                    String answer = message.getString("content").trim();

                    // Cache and return
                    answerCache.put(cacheKey, new CacheEntry(answer, System.currentTimeMillis() / 1000));
                    logger.debug("Cached answer for question: {}", question);

                    return answer;

                } catch (Exception e) {
                    logger.error("Request failed on attempt {}: {}", attempt, e.getMessage());
                    if (attempt == 3) {
                        return "Failed after retries: " + e.getMessage();
                    }
                    Thread.sleep(2000L * attempt);
                }
            }

            logger.error("Failed to get response after retries");
            return "Failed to get response after retries.";

        } catch (Exception e) {
            logger.error("Unexpected error: {}", e.getMessage());
            return "Something went wrong: " + e.getMessage();
        }
    }
}
